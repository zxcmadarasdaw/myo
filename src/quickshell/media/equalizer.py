#!/usr/bin/env python3
"""Transactional UI adapter for the existing serpantinum-audio ctl set protocol.

No installation, daemon startup, routing changes or PipeWire restarts here.
The ctl exit status acknowledges delivery, not an acoustic measurement.
"""
import copy
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys

PRESETS = {
    "Flat": [0]*10, "Bass": [5,7,5,2,1,0,0,0,1,2],
    "Bass Boost": [5,7,5,2,1,0,0,0,1,2],
    "Treble": [-2,-1,0,1,2,3,4,5,6,6],
    "Vocal": [-2,-1,1,3,5,5,4,2,1,0], "Pop": [2,4,2,0,1,2,4,2,1,2],
    "Rock": [5,4,2,-1,-2,-1,2,4,5,6], "Jazz": [3,3,1,1,1,1,2,1,2,3],
    "Classic": [0,1,2,2,2,2,1,2,3,4],
    "Electronic": [5,4,2,0,-1,1,2,3,4,3], "Cinema": [4,3,1,0,2,3,2,1,2,2],
}
DEFAULT = dict(zip((f"b{i}" for i in range(1,11)), [0]*10),
               preset="Flat", pending=False, balance=0, mono=False, swap=False,
               dynamics="off", dyneq=False, effects=True)


def number(value, low, high):
    value = float(value)
    if not math.isfinite(value) or not low <= value <= high:
        raise ValueError(f"Value must be between {low} and {high}")
    return value


def validated(data):
    out = dict(DEFAULT)
    for i in range(1,11):
        out[f"b{i}"] = number(data.get(f"b{i}", 0), -12, 12)
    out["balance"] = number(data.get("balance", 0), -1, 1)
    for key in ("mono", "swap", "dyneq", "effects"):
        out[key] = data.get(key, DEFAULT[key]) is True
    out["dynamics"] = data.get("dynamics", "off")
    if out["dynamics"] not in ("off", "balanced", "night"):
        raise ValueError("Invalid dynamics mode")
    out["preset"] = str(data.get("preset", "Custom"))[:80]
    return out


def atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".tmp.{os.getpid()}")
    try:
        tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


class Equalizer:
    def __init__(self, state_dir=None, run_dir=None, runner=subprocess.run):
        self.state_dir = Path(state_dir or Path(os.environ.get("XDG_STATE_HOME", str(Path.home()/".local/state")))/"serpantinum")
        self.run_dir = Path(run_dir or Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))/"serpantinum/music")
        self.saved = self.state_dir / "music/studio.json"
        self.cache = self.run_dir / "eq_state.json"
        self.presets_file = self.state_dir / "music/studio_presets.json"
        self.runner = runner

    def read(self):
        if self.saved.exists():
            return validated(json.loads(self.saved.read_text(encoding="utf-8")))
        daemon = self.state_dir / "audio.state"
        if daemon.exists():
            fields = daemon.read_text().split()
            if len(fields) >= 16 and fields[0] == "set":
                data = dict(zip((f"b{i}" for i in range(1,11)), fields[1:11]))
                data.update(balance=fields[11], mono=fields[12] == "1", swap=fields[13] == "1",
                            dynamics=fields[14], dyneq=len(fields)>16 and fields[16] == "1")
                gains = [float(x) for x in fields[1:11]]
                data["preset"] = next((k for k,v in PRESETS.items() if v == gains), "Custom")
                return validated(data)
        if self.cache.exists():
            data = json.loads(self.cache.read_text(encoding="utf-8"))
            # The old UI staged bands without sending them. Never call a draft applied.
            if not data.get("pending", False):
                return validated(data)
        return dict(DEFAULT)

    def custom_presets(self):
        if not self.presets_file.exists():
            return {}
        data = json.loads(self.presets_file.read_text(encoding="utf-8"))
        return {str(k)[:80]: validated(v) for k,v in data.items()}

    def status(self):
        if not shutil.which("serpantinum-audio"):
            return False, "Не найден serpantinum-audio. Нужен штатный аудиокомпонент Serpantinum."
        if not shutil.which("pw-dump"):
            return False, "Не найден pw-dump: невозможно проверить подключение к PipeWire."
        try:
            result = self.runner(["pw-dump"], capture_output=True, text=True, timeout=3, check=True)
            nodes = json.loads(result.stdout)
            if any(n.get("info", {}).get("props", {}).get("node.name") == "serpantinum_sink" for n in nodes):
                return True, ""
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
        return False, "Аудиодвижок не подключён к PipeWire. Проверьте serpantinum-audio и устройство вывода."

    def send(self, data):
        # Neutral processing is bypass; do not stop the shared daemon or alter routing.
        actual = data if data["effects"] else DEFAULT
        args = [str(actual[f"b{i}"]) for i in range(1,11)]
        args += [str(actual["balance"]), str(int(actual["mono"])), str(int(actual["swap"])),
                 actual["dynamics"], "0", str(int(actual["dyneq"]))]
        self.runner(["serpantinum-audio", "ctl", "set", *args],
                    capture_output=True, text=True, timeout=4, check=True)

    def execute(self, command, args):
        state = self.read()
        custom = self.custom_presets()
        if command in ("get", "status"):
            return state
        if command == "save_preset":
            name = args[0].strip()
            if not name or len(name)>60 or name in PRESETS or len(custom)>=64 and name not in custom:
                raise ValueError("Choose a unique preset name (1–60 characters, at most 64 presets)")
            custom[name] = state
            atomic(self.presets_file, custom)
            return state
        new = copy.deepcopy(state)
        if command == "set_band":
            band = int(args[0])
            if not 1 <= band <= 10:
                raise ValueError("Invalid EQ band")
            new[f"b{band}"] = number(args[1], -12, 12)
            new["preset"] = "Custom"
        elif command == "set_tone":
            bands = {"bass": (1,2,3), "mid": (4,5,6,7), "treble": (8,9,10)}[args[0]]
            for band in bands:
                new[f"b{band}"] = number(args[1], -12, 12)
            new["preset"] = "Custom"
        elif command == "preset":
            if args[0] in PRESETS:
                new.update({f"b{i+1}": v for i,v in enumerate(PRESETS[args[0]])})
                new["preset"] = args[0]
            elif args[0] in custom:
                new = dict(custom[args[0]], effects=state["effects"], preset=args[0])
            else:
                raise ValueError("Unknown preset")
        elif command == "set_balance":
            new["balance"] = number(args[0], -1, 1)
        elif command in ("set_mono", "set_swap", "set_dyneq", "set_effects"):
            if args[0] not in ("true", "false"):
                raise ValueError("Invalid switch value")
            new[command[4:]] = args[0] == "true"
        elif command == "set_dynamics":
            new["dynamics"] = args[0]
        elif command == "reset_audio":
            new.update(balance=0, mono=False, swap=False, dynamics="off")
        elif command == "reset":
            new = dict(DEFAULT, effects=state["effects"])
        elif command != "apply":
            raise ValueError("Unknown equalizer command")
        new = validated(new)
        if not new["effects"] and command not in ("set_effects", "reset"):
            raise ValueError("Enable effects before editing")
        self.send(new)  # Never publish a successful state until ctl succeeds.
        atomic(self.saved, new)
        atomic(self.cache, new)
        return new


def main():
    eq = Equalizer()
    eq.run_dir.mkdir(parents=True, exist_ok=True)
    # All callers, including the legacy shell entry, share this lock.
    import fcntl
    with (eq.run_dir / "equalizer.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            command = sys.argv[1] if len(sys.argv)>1 else "status"
            state = eq.execute(command, sys.argv[2:])
            available, reason = eq.status() if command in ("status", "get", "save_preset") else (True, "")
            print(json.dumps(dict(ok=True, state=state, available=available, error=reason,
                                  presets=list(PRESETS)+list(eq.custom_presets())), ensure_ascii=False))
        except (OSError, ValueError, KeyError, IndexError, subprocess.SubprocessError) as exc:
            print(json.dumps(dict(ok=False, available=False, error=f"Audio Studio: {exc}"), ensure_ascii=False))
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
