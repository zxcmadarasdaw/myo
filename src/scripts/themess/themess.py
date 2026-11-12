"""Scan and apply data-only desktop packages through Serpantinum's native stores."""
import argparse
import base64
import copy
from dataclasses import dataclass, field
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import tempfile

from schema import SETTINGS, configuration, plain, widget_layout

JSON_LIMIT = 2 * 1024 * 1024
MEDIA_LIMIT = 24 * 1024 * 1024
FORMATS = {
    ".gif": ("gif", (b"GIF87a", b"GIF89a")),
    ".png": ("png_pipe", (b"\x89PNG\r\n\x1a\n",)),
    ".jpg": ("jpeg_pipe", (b"\xff\xd8\xff",)),
    ".jpeg": ("jpeg_pipe", (b"\xff\xd8\xff",)),
    ".webp": ("webp_pipe", (b"RIFF",)),
}
FALLBACK = {kind: f"{kind}.json" for kind in (*SETTINGS, "widgets")}
KINDS = set(FALLBACK) | {"wallpaper"}


def encode(value):
    return (json.dumps(value, ensure_ascii=True, indent=2, allow_nan=False) + "\n").encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_json(data):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result or key in {"__proto__", "prototype", "constructor", "hasOwnProperty"}:
                raise ValueError(f"invalid or duplicate JSON key: {key}")
            result[key] = value
        return result

    def invalid_constant(value):
        raise ValueError(f"invalid JSON number: {value}")

    return json.loads(data.decode("utf-8-sig"), object_pairs_hook=unique, parse_constant=invalid_constant)


def relative_parts(name):
    if not isinstance(name, str) or len(name) > 300 or re.search(r'[\\:\x00-\x1f\x7f]', name):
        raise ValueError("expected a relative package path")
    parts = name.split("/")
    if any(part in ("", ".", "..") for part in parts):
        raise ValueError(f"unsafe package path: {name}")
    return parts


def read_package_file(root, name, limit):
    parts = relative_parts(name)
    if os.open in os.supports_dir_fd and hasattr(os, "O_NOFOLLOW"):
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        directory = os.open(root.anchor, flags)
        try:
            for part in (*root.parts[1:], *parts[:-1]):
                child = os.open(part, flags, dir_fd=directory)
                os.close(directory)
                directory = child
            fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
            with os.fdopen(fd, "rb") as stream:
                if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                    raise ValueError(f"{name}: expected a regular file")
                data = stream.read(limit + 1)
        finally:
            os.close(directory)
    else:
        path = root
        for part in parts:
            path = path / part
            if path.is_symlink() or (hasattr(path, "is_junction") and path.is_junction()):
                raise ValueError(f"{name}: links are unsupported")
        if not path.is_file():
            raise ValueError(f"{name}: expected a regular file")
        with path.open("rb") as stream:
            data = stream.read(limit + 1)
    if not data or len(data) > limit:
        raise ValueError(f"{name}: file is empty or exceeds {limit} bytes")
    return data


def image_snapshot(data, suffix, size=(1920, 1080)):
    demuxer, prefixes = FORMATS[suffix]
    if not data.startswith(prefixes) or (suffix == ".webp" and data[8:12] != b"WEBP"):
        raise ValueError("wallpaper data does not match its extension")
    # Feed immutable bytes to a forced demuxer. The decoder cannot open package paths.
    command = ["ffmpeg", "-nostdin", "-v", "error", "-xerror", "-protocol_whitelist", "pipe",
               "-max_pixels", "16777216", "-threads", "2", "-f", demuxer, "-i", "pipe:0"]
    try:
        if suffix == ".gif":
            subprocess.run(command + ["-f", "null", "-"], input=data, capture_output=True,
                           timeout=15, check=True)
        process = subprocess.run(command + ["-frames:v", "1", "-vf",
                                            f"scale='min({size[0]},iw)':'min({size[1]},ih)':force_original_aspect_ratio=decrease", "-threads", "1",
                                            "-c:v", "png", "-f", "image2pipe", "pipe:1"],
                                 input=data, capture_output=True, timeout=15, check=True)
    except FileNotFoundError as error:
        raise ValueError("ffmpeg is required to validate wallpaper") from error
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise ValueError("wallpaper could not be decoded within the supported image limits") from error
    if not process.stdout.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("wallpaper contains no decodable frame")
    return process.stdout


def merge(target, patch):
    for key, value in patch.items():
        if isinstance(value, dict):
            current = target.get(key)
            target[key] = current if isinstance(current, dict) else {}
            merge(target[key], value)
        else:
            target[key] = value


def differences(before, after, prefix=""):
    changes = []
    for key, value in after.items():
        if isinstance(value, dict):
            current = before.get(key)
            changes.extend(differences(current if isinstance(current, dict) else {}, value, f"{prefix}{key}."))
        elif key not in before or before[key] != value:
            changes.append({"setting": prefix + key, "before": before.get(key), "after": value})
    return changes


@dataclass
class Plan:
    root: Path
    name: str
    source: str = "structure"
    author: str = ""
    description: str = ""
    components: list = field(default_factory=list)
    warnings: list = field(default_factory=list)
    errors: list = field(default_factory=list)
    settings: dict = field(default_factory=dict)
    widgets: list | None = None
    image: tuple | None = None
    fingerprints: dict = field(default_factory=dict)


def manifest(plan):
    path = plan.root / "theme.json"
    if os.path.lexists(path):
        raw = read_package_file(plan.root, "theme.json", JSON_LIMIT)
        plan.fingerprints["theme.json"] = digest(raw)
        plan.source = "theme.json"
        data = read_json(raw)
        required = {"version", "name", "components"}
        optional = {"author", "description"}
        if (not isinstance(data, dict) or not required <= data.keys() <= required | optional
                or type(data["version"]) is not int or data["version"] != 1
                or not plain(data["name"]) or not isinstance(data["components"], dict)):
            raise ValueError("theme.json: expected version 1, name and components")
        plan.name = data["name"]
        if "author" in data:
            if not plain(data["author"]):
                raise ValueError("theme.json: invalid author")
            plan.author = data["author"]
        if "description" in data:
            description = data["description"]
            if not isinstance(description, str) or not 0 < len(description) <= 400 or not description.isprintable():
                raise ValueError("theme.json: invalid description")
            plan.description = description
        return data["components"]

    files = {key: name for key, name in FALLBACK.items() if os.path.lexists(plan.root / name)}
    candidates = [f"{base}{suffix}" for base in ("wallpaper", "wallpapers/wallpaper")
                  for suffix in FORMATS if os.path.lexists(plan.root / f"{base}{suffix}")]
    if len(candidates) > 1:
        raise ValueError("Multiple default wallpapers. Choose one in theme.json.")
    if candidates:
        files["wallpaper"] = candidates[0]
    return files


def scan(folder, caps, thumbnail=False):
    if not folder or not Path(folder).is_absolute():
        raise ValueError("Select an absolute package folder.")
    root = Path(folder).resolve(strict=True)
    if not root.is_dir():
        raise ValueError("Select a package folder.")
    plan = Plan(root, root.name)
    try:
        files = manifest(plan)
    except (OSError, ValueError, RecursionError) as error:
        plan.errors.append(str(error))
        return plan

    for kind, name in files.items():
        if kind not in KINDS:
            plan.warnings.append(f"{kind}: unknown component, ignored")
            continue
        if kind not in caps.get("modules", []):
            plan.warnings.append(f"{kind}: module unavailable in this session")
            continue
        try:
            parts = relative_parts(name)
            suffix = PurePosixPath(parts[-1]).suffix.lower()
            if kind == "wallpaper":
                if suffix not in FORMATS:
                    raise ValueError("expected a GIF, PNG, JPEG or WebP wallpaper")
                data = read_package_file(root, name, MEDIA_LIMIT)
                size = (480, 270) if thumbnail else (1920, 1080)
                plan.image = (name, suffix, data, image_snapshot(data, suffix, size))
            else:
                if suffix != ".json":
                    raise ValueError("expected a JSON file")
                data = read_package_file(root, name, JSON_LIMIT)
                value = read_json(data)
                if kind == "widgets":
                    plan.widgets = widget_layout(value, caps)
                else:
                    section, patch = configuration(kind, value, caps, plan.name)
                    merge(plan.settings, {section: patch})
            plan.fingerprints[name] = digest(data)
            plan.components.append({"kind": kind, "file": name})
        except (OSError, ValueError, RecursionError) as error:
            plan.errors.append(f"{kind}: {error}")
    if not plan.components and not plan.errors:
        plan.errors.append("No applicable components found.")
    return plan


class Stores:
    def __init__(self, caps):
        self.home = Path.home().resolve()
        self.settings = Path(os.getenv("QS_SETTINGS") or self.home / ".config/serpantinum/settings.json")
        self.state = Path(os.getenv("QS_STATE_DIR") or self.home / ".local/state/serpantinum")
        self.cache = Path(os.getenv("QS_CACHE_WALLPAPER") or
                          Path(os.getenv("QS_CACHE_DIR") or self.home / ".cache/serpantinum") / "wallpaper")
        self.directory = self.safe(Path(os.getenv("QS_STATE_THEMESS") or self.state / "themess"))
        self.caps = caps

    def safe(self, path):
        if not path.is_absolute() or path.is_symlink():
            raise ValueError(f"Invalid Serpantinum store path: {path}")
        result = path.resolve()
        if not result.is_relative_to(self.home) or result == self.home:
            raise ValueError(f"Serpantinum store must be inside the user home: {path}")
        return result

    def widget_path(self, screen):
        safe_name = re.sub(r"[^A-Za-z0-9_-]", "_", screen)
        base = Path(os.getenv(f"QS_STATE_WIDGETS/{safe_name.upper()}") or self.state / "widgets" / safe_name)
        return self.safe(base / "layout.json")

    def wallpaper_paths(self, screen):
        if not screen or re.search(r"[/\\\x00-\x1f]", screen):
            raise ValueError("Invalid wallpaper output name.")
        return tuple(self.safe(self.cache / name) for name in (
            f"current_{screen}", f"current_{screen}_name", f"current_wallpaper_{screen}.png"))


def snapshot(path):
    try:
        if not stat.S_ISREG(path.stat().st_mode):
            raise ValueError(f"Expected a regular store file: {path}")
        with path.open("rb") as stream:
            data = stream.read(MEDIA_LIMIT + 1)
    except FileNotFoundError:
        return None
    if len(data) > MEDIA_LIMIT:
        raise ValueError(f"Store file is too large to back up: {path}")
    return data


def write_atomic(path, data):
    if data is None:
        path.unlink(missing_ok=True)
        return
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    fd, temp = tempfile.mkstemp(prefix=".themess-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            if hasattr(os, "fchmod"):
                os.fchmod(stream.fileno(), mode)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        Path(temp).unlink(missing_ok=True)


def native_changes(plan, stores):
    targets = {}
    detail = {"settings": [], "widgetCount": None, "widgetScreen": "", "wallpaperScreens": []}
    if plan.settings:
        path = stores.safe(stores.settings)
        original = snapshot(path)
        current = read_json(original) if original else {}
        if not isinstance(current, dict):
            raise ValueError("Current settings.json must contain an object.")
        updated = copy.deepcopy(current)
        merge(updated, plan.settings)
        detail["settings"] = differences(current, plan.settings)
        if updated != current:
            targets[path] = (original, encode(updated))
    if plan.widgets is not None:
        screen = stores.caps.get("widgetScreen")
        if not screen:
            raise ValueError("No widget output is available.")
        path = stores.widget_path(screen)
        targets[path] = (snapshot(path), encode(plan.widgets))
        detail.update(widgetCount=len(plan.widgets), widgetScreen=screen)
    if plan.image:
        name, suffix, data, frame = plan.image
        asset = stores.safe(stores.directory / "assets" / (digest(data) + suffix))
        screens = stores.caps.get("wallpaperScreens", [])
        if not screens:
            raise ValueError("No wallpaper output is available.")
        preview = stores.safe(stores.cache / "current_wallpaper.png")
        targets[preview] = (snapshot(preview), frame)
        for screen in screens:
            current, title, preview = stores.wallpaper_paths(screen)
            targets[title] = (snapshot(title), PurePosixPath(name).name.encode("utf-8"))
            targets[preview] = (snapshot(preview), frame)
            targets[current] = (snapshot(current), str(asset).encode("utf-8"))
        detail["wallpaperScreens"] = screens
    return {path: pair for path, pair in targets.items() if pair[0] != pair[1]}, detail


def package_view(plan, show_image=False):
    info = {"folder": str(plan.root), "url": plan.root.as_uri(), "name": plan.name,
            "author": plan.author, "description": plan.description, "source": plan.source,
            "components": plan.components, "errors": plan.errors, "warnings": plan.warnings,
            "appearance": plan.settings, "widgets": plan.widgets,
            "packageToken": digest(encode([plan.fingerprints, plan.components, plan.warnings]))}
    if show_image and plan.image:
        info["image"] = "data:image/png;base64," + base64.b64encode(plan.image[3]).decode("ascii")
    return info


def report(plan, stores, preview=False):
    info = package_view(plan, preview)
    changes = {}
    if not plan.errors:
        changes, detail = native_changes(plan, stores)
        info.update(detail)
        info["token"] = digest(encode([str(plan.root), plan.fingerprints, detail,
                                       [[str(path), digest(before) if before is not None else None, digest(after)]
                                        for path, (before, after) in changes.items()]]))
        info["changed"] = bool(changes)
    info["preview"] = preview
    return info, changes


def journal_entry(changes):
    return {str(path): base64.b64encode(before).decode("ascii") if before is not None else None
            for path, (before, _) in changes.items()}


def restore_files(entries, stores):
    errors = []
    for name, data in entries.items():
        try:
            write_atomic(stores.safe(Path(name)), base64.b64decode(data, validate=True) if data is not None else None)
        except (ValueError, OSError) as error:
            errors.append(f"{name}: {error}")
    if errors:
        raise ValueError("Rollback could not restore " + "; ".join(errors))


def metadata(stores):
    path = stores.safe(stores.directory / "state.json")
    state = json.loads(path.read_bytes()) if path.exists() else {"history": [], "previous": None, "pending": None}
    if "active" not in state:
        state["active"] = (state["history"] or [None])[0] if state["previous"] is not None else None
    state.setdefault("previousActive", None)
    state.setdefault("original", state["previous"])
    state.setdefault("imported", [])
    state.setdefault("hidden", [])
    return state


def update_stores(stores, state, changes, finished):
    path = stores.safe(stores.directory / "state.json")
    before_images = journal_entry(changes)
    pending = dict(state, pending={
        str(target): {"before": before_images[str(target)], "after": digest(after) if after is not None else None}
        for target, (_, after) in changes.items()
    })
    write_atomic(path, encode(pending))
    written = {}
    try:
        for target, (before, after) in changes.items():
            if snapshot(target) != before:
                raise ValueError(f"Settings changed during the operation: {target}")
            write_atomic(target, after)
            written[str(target)] = before_images[str(target)]
        write_atomic(path, encode(finished))
    except (ValueError, OSError):
        restore_files(written, stores)
        write_atomic(path, encode(state))
        raise


def status(state):
    active = state["active"]
    return {
        "history": state["history"],
        "canRestore": state["previous"] is not None or state["pending"] is not None,
        "canRestoreOriginal": state["original"] is not None,
        "active": {"folder": active, "name": state.get("activeName") or Path(active).name} if active else None,
    }


def catalog(stores, state):
    paths = set(state["imported"]) | set(state["history"])
    roots = {Path(__file__).resolve().parents[3] / "themess", stores.home / ".local/share/serpantinum/themess"}
    for root in roots:
        if not root.is_dir():
            continue
        for entry in root.iterdir():
            if not entry.is_dir() or entry.name.startswith("."):
                continue
            known = ("theme.json", *FALLBACK.values(),
                     *(f"{base}{suffix}" for base in ("wallpaper", "wallpapers/wallpaper") for suffix in FORMATS))
            if any(os.path.lexists(entry / name) for name in known):
                paths.add(str(entry.resolve()))
    packages = []
    for path in sorted(paths - set(state["hidden"])):
        try:
            plan = scan(path, stores.caps, thumbnail=True)
        except (OSError, ValueError, RecursionError) as error:
            plan = Plan(Path(path), Path(path).name, errors=[str(error)])
        item = package_view(plan, show_image=True)
        item["available"] = plan.root.is_dir()
        packages.append(item)
    packages.sort(key=lambda item: (item["folder"] != state["active"], item["name"].casefold()))
    return dict(status(state), packages=packages)


def edit_library(args, stores, state):
    folder = Path(args.folder)
    if not folder.is_absolute():
        raise ValueError("Select an absolute package folder.")
    folder = folder.resolve(strict=args.action == "import")
    path = str(folder)
    imported = [item for item in state["imported"] if item != path]
    hidden = [item for item in state["hidden"] if item != path]
    if args.action == "import":
        if not folder.is_dir():
            raise ValueError("Select a package folder.")
        imported.append(path)
    else:
        hidden.append(path)
    finished = dict(state, imported=imported, hidden=hidden)
    write_atomic(stores.directory / "state.json", encode(finished))
    return dict(status(finished), selection=path if args.action == "import" else "",
                message="Folder added to library." if args.action == "import" else "Package removed from library.")


def recover_pending(stores, pending):
    restore = {}
    for name, record in pending.items():
        path = stores.safe(Path(name))
        current = snapshot(path)
        before = base64.b64decode(record["before"], validate=True) if record["before"] is not None else None
        if current == before:
            continue
        current_digest = digest(current) if current is not None else None
        if current_digest != record["after"]:
            raise ValueError(f"Interrupted transaction conflicts with later edits: {path}")
        restore[name] = record["before"]
    restore_files(restore, stores)


def acquire_lock(lock):
    try:
        if os.name == "nt":
            import msvcrt
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as error:
        raise ValueError("Another Themess operation is running.") from error


def mutate(args, stores):
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        raise ValueError("Run Themess as the desktop user.")
    stores.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock_path = stores.safe(stores.directory / "lock")
    with lock_path.open("a+b") as lock:
        acquire_lock(lock)
        state = metadata(stores)
        if args.action in ("import", "remove"):
            return edit_library(args, stores, state)
        recovered = state["pending"] is not None
        if recovered:
            recover_pending(stores, state["pending"])
            state["pending"] = None
            write_atomic(stores.directory / "state.json", encode(state))
        if args.action in ("restore", "restore-original"):
            if recovered:
                return dict(status(state), message="Interrupted Themess operation rolled back.")
            original = args.action == "restore-original"
            backup = state["original" if original else "previous"]
            if backup is None:
                raise ValueError("No Themess backup is available for this action.")
            changes = {}
            for name, data in backup.items():
                path = stores.safe(Path(name))
                changes[path] = (snapshot(path), base64.b64decode(data, validate=True) if data is not None else None)
            active = None if original else state["previousActive"]
            finished = dict(state, previous=None, previousActive=None, previousName=None,
                            active=active, activeName=state.get("previousName") if active else None,
                            original=state["original"] if active else None)
            update_stores(stores, state, changes, finished)
            return dict(status(finished), message=("Original desktop settings restored." if original
                                                   else "Previous desktop settings restored."))

        plan = scan(args.folder, stores.caps)
        info, changes = report(plan, stores)
        if plan.errors:
            return dict(status(state), **info)
        if not args.token or args.token != info["token"]:
            raise ValueError("Package, desktop settings or outputs changed. Scan again before applying.")
        if plan.image and changes:
            _, suffix, data, _ = plan.image
            asset = stores.safe(stores.directory / "assets" / (digest(data) + suffix))
            if snapshot(asset) != data:
                write_atomic(asset, data)
        folder = str(plan.root)
        history = [folder] + [item for item in state["history"] if item != folder]
        backup = journal_entry(changes)
        finished = dict(state, history=history[:12], active=folder, activeName=plan.name)
        if changes or folder != state["active"]:
            # Keep the first backup of each native file across successive packages.
            original = dict(backup)
            original.update(state["original"] or {})
            finished.update(previous=backup, previousActive=state["active"], previousName=state.get("activeName"),
                            original=original)
        if changes:
            update_stores(stores, state, changes, finished)
        else:
            write_atomic(stores.directory / "state.json", encode(finished))
        message = "Package applied." if changes else "The selected settings are already active."
        return dict(status(finished), message=message)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("status", "catalog", "import", "remove", "scan", "preview", "apply", "restore", "restore-original"))
    parser.add_argument("--folder", default="")
    parser.add_argument("--token", default="")
    parser.add_argument("--caps", default="{}")
    args = parser.parse_args()
    stores = None
    try:
        stores = Stores(json.loads(args.caps))
        if args.action == "status":
            result = status(metadata(stores))
        elif args.action == "catalog":
            result = catalog(stores, metadata(stores))
        elif args.action in ("scan", "preview"):
            result, _ = report(scan(args.folder, stores.caps), stores, args.action == "preview")
        else:
            result = mutate(args, stores)
    except (OSError, ValueError, RecursionError) as error:
        result = {"errors": [str(error)]}
        if stores is not None and args.action in ("apply", "restore", "restore-original"):
            try:
                result.update(status(metadata(stores)))
            except (OSError, ValueError):
                pass
    print(json.dumps(result, ensure_ascii=True))
    return 1 if result.get("errors") else 0


if __name__ == "__main__":
    sys.exit(main())
