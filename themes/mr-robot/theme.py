#!/usr/bin/env python3
"""Apply the Mr. Robot preset to an existing Serpantinum installation."""

import argparse
import json
import math
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import time


PACK = Path(__file__).resolve().parent
FRAGMENTS = ("palette.json", "panels.json", "animations.json", "canvas.json")
ASSETS = ("mr-robot.gif", "mr-robot.webm", "mr-robot-still.png")


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def read_object(path):
    data = json.loads(path.read_bytes())
    if not isinstance(data, dict):
        raise ValueError(f"Ожидался объект JSON в {path}")
    return data


def merge(target, fragment):
    for key, value in fragment.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            merge(target[key], value)
        else:
            target[key] = value


def make_layout(width, height, preset):
    # Keep native widget dimensions. Use the canvas camera to fit small screens.
    zoom = math.floor(min(1, width / 1000, height / 640) * 10000) / 10000
    if zoom < 0.2:
        raise ValueError("Экран меньше минимальной области Infinite Canvas")
    world_width, world_height = int(width / zoom), int(height / zoom)
    layout = []
    for entry in preset["widgets"]:
        item = dict(entry)
        vertical, horizontal = item.pop("anchor").split()
        x, y = item.pop("x"), item.pop("y")
        w, h = item.pop("w"), item.pop("h")
        item.update(
            wId=item.pop("id"), wType=item["type"], wVariant=item.pop("variant"),
            wX=world_width - w - x if horizontal == "right" else x,
            wY=world_height - h - y if vertical == "bottom" else y,
            wWidth=w, wHeight=h, wOpacity=1, wRotation=0, wImagePath="",
        )
        layout.append(item)
    camera = {
        "schema_version": 1,
        "camera": {"x": 0, "y": 0, "zoom": zoom},
        "screen": {"w": width, "h": height},
    }
    return layout, camera


def choose_monitor(monitors, requested):
    active = [m for m in monitors if not m.get("disabled") and m.get("dpmsStatus", True)]
    if not active:
        raise ValueError("Hyprland не сообщает об активных мониторах")
    if requested:
        monitor = next((m for m in active if m["name"] == requested), None)
        if monitor is None:
            raise ValueError(f"Монитор {requested} не активен")
    else:
        monitor = next((m for m in active if m.get("focused")), active[0])
    name = monitor["name"]
    if not re.fullmatch(r"[A-Za-z0-9_-]+", name):
        raise ValueError(f"Неподдерживаемое имя выхода Hyprland {name!r}")
    width, height = monitor["width"], monitor["height"]
    if monitor.get("transform", 0) % 2:
        width, height = height, width
    scale = monitor["scale"]
    if not math.isfinite(scale) or scale <= 0:
        raise ValueError(f"Некорректный масштаб выхода {name}")
    return name, round(width / scale), round(height / scale)


def apply_settings(settings, name):
    canvas_values = read_object(PACK / "canvas.json")["canvas"]
    for filename in FRAGMENTS:
        merge(settings, read_object(PACK / filename))
    # A previous per-output override takes precedence over global settings.
    overrides = settings["canvas"].get("monitors")
    if isinstance(overrides, dict) and isinstance(overrides.get(name), dict):
        merge(overrides[name], canvas_values)


def import_preset(settings, name):
    apply_settings(settings, name)
    widgets = read_object(PACK / "widgets.json")["widgets"]
    for widget in widgets:
        if widget["anchor"].startswith("top "):
            # The native importer adds the bar's height to top-anchored offsets.
            widget["y"] -= 44
    return {
        "name": "Mr. Robot",
        "palette": settings["theme"]["colors"],
        "settings": settings,
        "widgets": {name: widgets},
    }


def plan(home, monitor, still):
    name, width, height = monitor
    settings_path = home / ".config/serpantinum/settings.json"
    settings = read_object(settings_path)
    apply_settings(settings, name)
    layout, camera = make_layout(width, height, read_object(PACK / "widgets.json"))
    widget_dir = home / ".local/state/serpantinum/widgets" / name
    camera_path = widget_dir / "canvas.json"
    if camera_path.exists() and read_object(camera_path).get("schema_version", 0) > 1:
        raise ValueError(f"Файл {camera_path} создан более новой версией Serpantinum")

    data_home = Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share")
    if not data_home.is_absolute():
        data_home = home / ".local/share"
    assets = data_home.resolve() / "serpantinum-themes/mr-robot/wallpapers"
    wallpaper = assets / (ASSETS[2] if still else ASSETS[1])
    cache = home / ".cache/serpantinum/wallpaper"
    poster = (PACK / "wallpapers" / ASSETS[2]).read_bytes()
    writes = {assets / asset: (PACK / "wallpapers" / asset).read_bytes() for asset in ASSETS}
    writes.update({
        widget_dir / "layout.json": json_bytes(layout),
        camera_path: json_bytes(camera),
        cache / f"current_wallpaper_{name}.png": poster,
        cache / "current_wallpaper.png": poster,
        cache / f"current_{name}": str(wallpaper).encode("utf-8"),
        cache / f"current_{name}_name": wallpaper.name.encode("utf-8"),
        settings_path: json_bytes(settings),
    })
    return writes, cache / "history.txt"


def file_mode(path):
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ValueError(f"Ожидался обычный файл или свободный путь {path}")
    return stat.S_IMODE(path.stat().st_mode) if path.exists() else None


def write_atomic(path, data, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".mr-robot-", delete=False) as temp:
        temporary = Path(temp.name)
        try:
            temp.write(data)
            temp.close()
            os.chmod(temporary, mode if mode is not None else 0o600)
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def save_backup(active, originals):
    with tempfile.TemporaryDirectory(dir=active.parent, prefix="backup-") as temp:
        folder = Path(temp)
        manifest = []
        for index, (path, mode) in enumerate(originals.items()):
            manifest.append({"path": str(path), "mode": mode})
            if mode is not None:
                (folder / str(index)).write_bytes(path.read_bytes())
        (folder / "manifest.json").write_bytes(json_bytes(manifest))
        folder.rename(active)


def restore(active):
    if not active.is_dir():
        raise ValueError("Активная резервная копия темы не найдена")
    manifest = json.loads((active / "manifest.json").read_bytes())
    originals = []
    for index, entry in enumerate(manifest):
        path, mode = Path(entry["path"]), entry["mode"]
        file_mode(path)
        data = (active / str(index)).read_bytes() if mode is not None else None
        originals.append((path, mode, data))
    for path, mode, data in reversed(originals):
        if data is None:
            path.unlink(missing_ok=True)
        else:
            write_atomic(path, data, mode)
    active.rename(active.with_name(f"restored-{time.time_ns()}"))


def installed_source():
    client = shutil.which("serpantinum")
    if client is None or shutil.which("serpantinumd") is None:
        raise ValueError("Команды serpantinum и serpantinumd должны быть в PATH")
    default = Path(client).resolve().parent.parent / "src"
    source = Path(os.environ.get("SERPANTINUM_DIR") or default)
    if not (source / "quickshell/widgets/canvas/CanvasHud.qml").is_file():
        raise ValueError(f"В установленной сборке не найден Infinite Canvas ({source})")
    if not (source / "quickshell/widgets/faces/clock/ClockFaceLockscreen.qml").is_file():
        raise ValueError(f"В установленной сборке не найден вариант часов lockscreen ({source})")


def require_stopped():
    status = subprocess.run(["serpantinumd", "status"], capture_output=True, text=True, check=False)
    if status.returncode != 1:
        raise ValueError("Остановите оболочку через serpantinumd stop перед изменением файлов")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("preset", "check", "apply", "restore"))
    parser.add_argument("--monitor", help="Выход Hyprland. По умолчанию активный монитор с фокусом.")
    parser.add_argument("--still", action="store_true", help="Использовать статичный кадр.")
    args = parser.parse_args()
    if args.action == "restore" and (args.monitor or args.still):
        parser.error("restore использует монитор и файлы из резервной копии")
    if args.action == "preset" and args.still:
        parser.error("При импорте JSON обои выбираются отдельно")

    if os.geteuid() == 0:
        raise ValueError("Запустите скрипт от пользователя сессии Hyprland")
    home = Path.home().resolve()
    active = home / ".local/state/serpantinum/mr-robot-theme/active"

    if args.action == "preset":
        installed_source()
        name, _, _ = detect_monitor(args.monitor)
        settings = read_object(home / ".config/serpantinum/settings.json")
        print(json_bytes(import_preset(settings, name)).decode("utf-8"), end="")
        return

    if args.action == "check":
        installed_source()
        monitor, writes, history = prepare(home, args)
        for path in (*writes, history):
            file_mode(path)
        print(f"Выход {monitor[0]}, логическая область {monitor[1]}×{monitor[2]}")
        print(*writes, sep="\n")
        print(f"Резервная копия → {active}")
        return

    import fcntl

    active.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (active.parent / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        require_stopped()
        if args.action == "restore":
            restore(active)
            print("Восстановлены файлы Serpantinum из резервной копии.")
            return
        if active.exists():
            raise ValueError(f"Тема уже применялась. Сначала выполните restore ({active})")
        installed_source()
        monitor, writes, history = prepare(home, args)
        originals = {path: file_mode(path) for path in (*writes, history)}
        save_backup(active, originals)
        try:
            for path, data in writes.items():
                write_atomic(path, data, originals[path])
        except (OSError, KeyboardInterrupt):
            restore(active)
            raise
        print(f"Тема применена к {monitor[0]}. Резервная копия → {active}")


def prepare(home, args):
    if not args.still and not shutil.which("ffmpeg"):
        raise ValueError("Для кадров предпросмотра видео нужен ffmpeg. Доступен режим --still")
    monitor = detect_monitor(args.monitor)
    writes, history = plan(home, monitor, args.still)
    return monitor, writes, history


def detect_monitor(requested):
    output = subprocess.check_output(["hyprctl", "-j", "monitors"], timeout=10)
    return choose_monitor(json.loads(output), requested)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Mr. Robot: {error}") from None
