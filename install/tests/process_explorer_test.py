"""Process Explorer backend (src/scripts/system/serp_procs.py) on a fake /proc.

    python3 install/tests/process_explorer_test.py

Builds a /proc and /sys tree in a temporary folder (SERP_PROC_ROOT /
SERP_SYS_ROOT) and checks: totals (CPU %, RAM, process count), htop-style
per-process CPU between two samples, a reused PID not being charged with the
old process's time, names with spaces and parentheses, GPU busy percent from
the DRM sysfs file, process details, and the `--once` JSON line. The backend
never signals processes, which is checked by scanning its source.
"""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "src/scripts/system/serp_procs.py"


def stat_line(pid, name, state="S", ppid=1, utime=0, stime=0, threads=1, start=1000):
    # fields after the name: state ppid pgrp session tty tpgid flags minflt cminflt majflt cmajflt
    #                        utime stime cutime cstime priority nice num_threads itrealvalue starttime
    rest = [state, ppid, pid, pid, 0, -1, 0, 0, 0, 0, 0, utime, stime, 0, 0, 20, 0, threads, 0, start, 0, 0]
    return f"{pid} ({name}) " + " ".join(str(x) for x in rest) + "\n"


class FakeSystem:
    def __init__(self, base):
        self.proc = base / "proc"
        self.sys = base / "sys"
        self.proc.mkdir()
        (self.proc / "meminfo").write_text("MemTotal:       16000000 kB\nMemFree:         2000000 kB\nMemAvailable:    8000000 kB\n")
        (self.proc / "uptime").write_text("5000.00 10000.00\n")
        self.set_cpu(user=1000, idle=9000)

    def set_cpu(self, user, idle):
        lines = [f"cpu  {user} 0 0 {idle} 0 0 0 0 0 0"]
        for i in range(4):
            lines.append(f"cpu{i} {user // 4} 0 0 {idle // 4} 0 0 0 0 0 0")
        (self.proc / "stat").write_text("\n".join(lines) + "\nintr 0\n")

    def add(self, pid, name, utime=0, cmd=None, rss_pages=256, start=1000):
        d = self.proc / str(pid)
        d.mkdir(exist_ok=True)
        (d / "stat").write_text(stat_line(pid, name, utime=utime, start=start))
        (d / "statm").write_text(f"1000 {rss_pages} 0 0 0 0 0\n")
        (d / "cmdline").write_bytes(("\0".join(cmd or [name]) + "\0").encode())
        (d / "status").write_text(f"Name:\t{name}\nVmRSS:\t{rss_pages * 4} kB\nThreads:\t1\n")

    def gpu(self, percent):
        dev = self.sys / "class/drm/card0/device"
        dev.mkdir(parents=True)
        (dev / "gpu_busy_percent").write_text(f"{percent}\n")


def load_module(proc_root, sys_root):
    os.environ["SERP_PROC_ROOT"] = str(proc_root)
    os.environ["SERP_SYS_ROOT"] = str(sys_root)
    spec = importlib.util.spec_from_file_location("serp_procs_under_test", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class ProcessExplorerBackendTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="serp-procs-")
        self.fs = FakeSystem(Path(self.tmp.name))
        self.fs.add(1, "systemd", utime=50)
        self.fs.add(200, "firefox", utime=100, cmd=["/usr/lib64/firefox/firefox", "--new-window"], rss_pages=100000)
        self.fs.add(300, "Web Content (pid) x", utime=10)
        self.fs.add(400, "idle", utime=5)
        self.mod = load_module(self.fs.proc, self.fs.sys)

    def tearDown(self):
        self.tmp.cleanup()
        os.environ.pop("SERP_PROC_ROOT", None)
        os.environ.pop("SERP_SYS_ROOT", None)

    def test_parse_stat_handles_spaces_and_parentheses(self):
        st = self.mod.parse_stat(stat_line(300, "Web Content (pid) x", utime=7, stime=3, threads=12, start=4242))
        self.assertEqual(st["name"], "Web Content (pid) x")
        self.assertEqual((st["ppid"], st["ticks"], st["threads"], st["starttime"]), (1, 10, 12, 4242))

    def test_totals_and_per_process_cpu(self):
        sampler = self.mod.Sampler()
        first = sampler.sample()
        self.assertEqual(first["count"], 4)
        self.assertEqual(first["cores"], 4)
        self.assertTrue(all(p["cpu"] == 0 for p in first["procs"]))      # one sample: no rates yet
        # 1000 jiffies pass on the machine: 250 busy (25 %), firefox used 200 of them
        self.fs.set_cpu(user=1250, idle=9750)
        self.fs.add(200, "firefox", utime=300, cmd=["/usr/lib64/firefox/firefox", "--new-window"], rss_pages=100000)
        snap = sampler.sample()
        self.assertEqual(snap["cpu"], 25.0)
        procs = {p["pid"]: p for p in snap["procs"]}
        self.assertEqual(procs[200]["cpu"], 80.0)                        # 200/1000 of 4 cores = 0.8 core
        self.assertEqual(procs[400]["cpu"], 0.0)
        self.assertEqual(procs[200]["mem"], 100000 * self.mod.PAGE)
        self.assertEqual(procs[200]["cmd"], "/usr/lib64/firefox/firefox --new-window")
        self.assertEqual(snap["ram"]["total"], 16000000 * 1024)
        self.assertEqual(snap["ram"]["used"], 8000000 * 1024)
        self.assertEqual(snap["ram"]["percent"], 50.0)
        if shutil.which("nvidia-smi") is None:
            self.assertIsNone(snap["gpu"])                                # no DRM busy file, no NVIDIA tool

    def test_reused_pid_is_not_charged(self):
        sampler = self.mod.Sampler()
        sampler.sample()
        self.fs.set_cpu(user=1250, idle=9750)
        self.fs.add(400, "newproc", utime=900, start=99999)               # same pid, new start time
        snap = sampler.sample()
        self.assertEqual({p["pid"]: p for p in snap["procs"]}[400]["cpu"], 0.0)

    def test_gpu_busy_percent(self):
        self.fs.gpu(37)
        self.assertEqual(self.mod.gpu_usage()["percent"], 37)

    def test_vanished_process_is_skipped(self):
        sampler = self.mod.Sampler()
        (self.fs.proc / "999").mkdir()                                    # no stat: exited mid-scan
        self.assertEqual(sampler.sample()["count"], 4)

    def test_detail(self):
        d = self.mod.detail(200)
        self.assertEqual(d["name"], "firefox")
        self.assertEqual(d["cmdline"], "/usr/lib64/firefox/firefox --new-window")
        self.assertIn("VmRSS", d["status"])
        self.assertEqual(self.mod.detail(31337), {"pid": 31337, "gone": True})

    def test_once_json_line(self):
        env = dict(os.environ, SERP_PROC_ROOT=str(self.fs.proc), SERP_SYS_ROOT=str(self.fs.sys))
        out = subprocess.run([sys.executable, str(SCRIPT), "--once", "--interval", "0.5"],
                             capture_output=True, text=True, env=env, timeout=20)
        self.assertEqual(out.returncode, 0, out.stderr)
        snap = json.loads(out.stdout.strip().splitlines()[-1])
        self.assertEqual(snap["count"], 4)
        self.assertEqual(sorted(p["pid"] for p in snap["procs"]), [1, 200, 300, 400])
        for key in ("cpu", "cores", "ram", "gpu", "self", "uid", "procs"):
            self.assertIn(key, snap)

    def test_backend_never_signals_processes(self):
        source = SCRIPT.read_text(encoding="utf-8")
        for forbidden in ("os.kill", "killpg", "signal.SIG", "subprocess.run([\"kill"):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
