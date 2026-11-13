#!/usr/bin/env python3
"""Process Explorer backend for Serpantinum.

    python3 serp_procs.py [--interval SECONDS] [--once]

Reads /proc directly (no psutil) and prints one JSON object per line:

  {"cpu": 12.5, "cores": 8, "ram": {"used": ..., "total": ..., "percent": ...},
   "gpu": {"percent": 30, "name": "amdgpu"} | null,
   "count": 312, "self": 1234, "uid": 1000,
   "procs": [{"pid", "ppid", "name", "cmd", "user", "uid", "own", "cpu", "mem",
              "threads", "state"}]}

CPU per process is htop-style: 100 means one full core. The first line only
has totals and zero per-process CPU (two samples are needed for a rate).

Commands on stdin, one per line:
  refresh            sample again now
  interval SECONDS   change the sampling interval (0.5 .. 30)
  detail PID         print {"detail": {...}} for one process

The shell starts this only while the Process Explorer panel is open. It never
signals processes itself; ending a process is done by the shell with `kill`
after the user confirms, and only for the user's own processes.
"""
import json
import os
import select
import sys
import time

try:
    import pwd
except ImportError:          # not on Linux (tests on other systems)
    pwd = None

PROC = os.environ.get("SERP_PROC_ROOT", "/proc")
SYS = os.environ.get("SERP_SYS_ROOT", "/sys")
CLK_TCK = os.sysconf("SC_CLK_TCK") if hasattr(os, "sysconf") else 100
PAGE = os.sysconf("SC_PAGE_SIZE") if hasattr(os, "sysconf") else 4096
MY_UID = os.getuid() if hasattr(os, "getuid") else -1

_users = {}


def user_name(uid):
    if uid not in _users:
        try:
            _users[uid] = pwd.getpwuid(uid).pw_name if pwd else str(uid)
        except KeyError:
            _users[uid] = str(uid)
    return _users[uid]


def read(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def cpu_times():
    """(total, idle) jiffies over all CPUs, and the core count."""
    text = read(os.path.join(PROC, "stat")) or ""
    total = idle = 0
    cores = 0
    for line in text.splitlines():
        if line.startswith("cpu "):
            v = [int(x) for x in line.split()[1:]]
            total = sum(v[:8])                # guest time is already counted in user
            idle = v[3] + (v[4] if len(v) > 4 else 0)
        elif line.startswith("cpu") and line[3:4].isdigit():
            cores += 1
    return total, idle, max(1, cores)


def memory():
    info = {}
    for line in (read(os.path.join(PROC, "meminfo")) or "").splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1].isdigit():
            info[parts[0].rstrip(":")] = int(parts[1]) * 1024
    total = info.get("MemTotal", 0)
    avail = info.get("MemAvailable", info.get("MemFree", 0))
    used = max(0, total - avail)
    return {"used": used, "total": total, "percent": round(used * 100.0 / total, 1) if total else 0}


def parse_stat(text):
    """Fields of /proc/PID/stat; the name may contain spaces and parentheses."""
    lpar, rpar = text.index("("), text.rindex(")")
    name = text[lpar + 1:rpar]
    rest = text[rpar + 2:].split()
    # rest[0] is field 3 (state); utime/stime are fields 14/15
    return {
        "name": name,
        "state": rest[0],
        "ppid": int(rest[1]),
        "ticks": int(rest[11]) + int(rest[12]),
        "nice": int(rest[16]),
        "threads": int(rest[17]),
        "starttime": int(rest[19]),
    }


def gpu_usage():
    """Busy percent of the first GPU whose driver reports one (amdgpu, recent i915/xe), or None."""
    base = os.path.join(SYS, "class", "drm")
    try:
        cards = sorted(c for c in os.listdir(base) if c.startswith("card") and "-" not in c)
    except OSError:
        cards = []
    for card in cards:
        busy = read(os.path.join(base, card, "device", "gpu_busy_percent"))
        if busy is not None and busy.strip().isdigit():
            driver = os.path.basename(os.path.realpath(os.path.join(base, card, "device", "driver")))
            return {"percent": int(busy.strip()), "name": driver or card}
    return None


class Sampler:
    def __init__(self):
        self.prev_ticks = {}
        self.prev_total = None
        self.prev_idle = None
        self.nvidia = None      # None: not tried yet, False: unavailable
        self.last_nvidia = None
        self.nvidia_at = 0.0

    def nvidia_usage(self):
        if self.nvidia is False:
            return None
        now = time.monotonic()
        if self.nvidia is not None and now - self.nvidia_at < 2.0:
            return self.last_nvidia
        import shutil
        import subprocess
        if shutil.which("nvidia-smi") is None:
            self.nvidia = False
            return None
        try:
            out = subprocess.run(["nvidia-smi", "--query-gpu=utilization.gpu,name", "--format=csv,noheader,nounits"],
                                 capture_output=True, text=True, timeout=2).stdout.strip().splitlines()
            pct, name = [x.strip() for x in out[0].split(",", 1)]
            self.nvidia = True
            self.last_nvidia = {"percent": int(float(pct)), "name": name}
        except Exception:
            self.nvidia = False
            self.last_nvidia = None
        self.nvidia_at = now
        return self.last_nvidia

    def sample(self):
        total, idle, cores = cpu_times()
        d_total = (total - self.prev_total) if self.prev_total is not None else 0
        d_idle = (idle - self.prev_idle) if self.prev_idle is not None else 0
        cpu = round(100.0 * (d_total - d_idle) / d_total, 1) if d_total > 0 else 0.0

        procs = []
        ticks_now = {}
        try:
            pids = [p for p in os.listdir(PROC) if p.isdigit()]
        except OSError:
            pids = []
        for p in pids:
            pid = int(p)
            stat = read(os.path.join(PROC, p, "stat"))
            if not stat:
                continue                      # exited between listdir and read
            try:
                st = parse_stat(stat)
            except (ValueError, IndexError):
                continue
            statm = (read(os.path.join(PROC, p, "statm")) or "0 0").split()
            rss = int(statm[1]) * PAGE if len(statm) > 1 and statm[1].isdigit() else 0
            try:
                uid = os.stat(os.path.join(PROC, p)).st_uid
            except OSError:
                continue
            cmd = (read(os.path.join(PROC, p, "cmdline")) or "").replace("\0", " ").strip()
            ticks_now[pid] = (st["ticks"], st["starttime"])
            prev = self.prev_ticks.get(pid)
            pcpu = 0.0
            # same pid and same start time: the same process
            if prev and prev[1] == st["starttime"] and d_total > 0:
                pcpu = round(100.0 * (st["ticks"] - prev[0]) * cores / d_total, 1)
            procs.append({
                "pid": pid,
                "ppid": st["ppid"],
                "name": st["name"],
                "cmd": cmd[:400],
                "uid": uid,
                "user": user_name(uid),
                "own": uid == MY_UID,
                "cpu": max(0.0, pcpu),
                "mem": rss,
                "threads": st["threads"],
                "state": st["state"],
            })
        self.prev_ticks = ticks_now
        self.prev_total, self.prev_idle = total, idle

        gpu = gpu_usage() or self.nvidia_usage()
        return {
            "cpu": cpu,
            "cores": cores,
            "ram": memory(),
            "gpu": gpu,
            "count": len(procs),
            "self": os.getppid(),
            "uid": MY_UID,
            "procs": procs,
        }


def detail(pid):
    base = os.path.join(PROC, str(pid))
    stat = read(os.path.join(base, "stat"))
    if not stat:
        return {"pid": pid, "gone": True}
    st = parse_stat(stat)
    status = {}
    for line in (read(os.path.join(base, "status")) or "").splitlines():
        k, _, v = line.partition(":")
        if k in ("VmRSS", "VmSize", "VmSwap", "Threads", "voluntary_ctxt_switches"):
            status[k] = v.strip()

    def link(name):
        try:
            return os.readlink(os.path.join(base, name))
        except OSError:
            return ""                         # other users' processes are not readable

    uptime_text = read(os.path.join(PROC, "uptime")) or "0"
    uptime = float(uptime_text.split()[0])
    started = time.time() - (uptime - st["starttime"] / CLK_TCK)
    try:
        uid = os.stat(base).st_uid
    except OSError:
        uid = -1
    return {
        "pid": pid,
        "ppid": st["ppid"],
        "name": st["name"],
        "state": st["state"],
        "nice": st["nice"],
        "threads": st["threads"],
        "user": user_name(uid) if uid >= 0 else "",
        "own": uid == MY_UID,
        "cmdline": (read(os.path.join(base, "cmdline")) or "").replace("\0", " ").strip(),
        "exe": link("exe"),
        "cwd": link("cwd"),
        "started": int(started),
        "status": status,
    }


def emit(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def handle(line, state):
    """Apply one stdin command; returns False when the stream ended."""
    if line == "":
        return False
    parts = line.strip().split()
    if parts[:1] == ["refresh"]:
        state["deadline"] = 0
    elif parts[:1] == ["interval"] and len(parts) > 1:
        try:
            state["interval"] = max(0.5, min(30.0, float(parts[1])))
        except ValueError:
            pass
    elif parts[:1] == ["detail"] and len(parts) > 1 and parts[1].isdigit():
        emit({"detail": detail(int(parts[1]))})
    return True


def main(argv):
    state = {"interval": 2.0, "deadline": 0.0}
    if "--interval" in argv:
        try:
            state["interval"] = max(0.5, min(30.0, float(argv[argv.index("--interval") + 1])))
        except (IndexError, ValueError):
            pass
    sampler = Sampler()
    sampler.sample()                          # prime the counters
    if "--once" in argv:
        time.sleep(min(state["interval"], 1.0))
        emit(sampler.sample())
        return 0
    time.sleep(0.4)                           # a first real rate quickly
    emit(sampler.sample())
    state["deadline"] = time.monotonic() + state["interval"]
    while True:
        timeout = max(0.0, state["deadline"] - time.monotonic())
        try:
            ready, _, _ = select.select([sys.stdin], [], [], timeout)
        except (OSError, ValueError):
            ready = []
            time.sleep(timeout)
        if ready:
            if not handle(sys.stdin.readline(), state):
                return 0                      # the shell went away
            continue
        if time.monotonic() >= state["deadline"]:
            emit(sampler.sample())
            state["deadline"] = time.monotonic() + state["interval"]


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (BrokenPipeError, KeyboardInterrupt):
        sys.exit(0)
