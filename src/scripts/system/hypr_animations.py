#!/usr/bin/env python3
"""Generate and apply the MYO-owned part of the Hyprland Lua configuration."""

import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time


LEAVES = ("open", "close", "move", "focus", "workspace", "special")
STYLES = {
    "open": ("fade", "scale", "zoom", "slide", "pop", "smooth", "off"),
    "workspace": ("slide", "slidevert", "fade", "slidefade", "slidefadevert", "off"),
    "special": ("fade", "slide", "slidevert", "slidefade", "slidefadevert", "off"),
    "move": ("smooth", "off"),
    "focus": ("fade", "off"),
}
STYLES["close"] = STYLES["open"]
CURVES = {
    "classic": ((0.05, 0.9), (0.1, 1.05)),
    "smooth": ((0.25, 0.1), (0.25, 1.0)),
    "linear": ((0, 0), (1, 1)),
    "pop": ((0.2, 0.75), (0.25, 1.35)),
    "abyss": ((0.16, 0.78), (0.27, 1.04)),
}
SIDES = ("auto", "left", "right", "top", "bottom")
MOVE_OPTIONS = ("animate_manual_resizes", "animate_mouse_windowdragging")
DEFAULTS = ("scale", "scale", "smooth", "fade", "slide", "fade")
PRESETS = {
    "classic": (500, "classic", DEFAULTS, 20),
    "smooth": (320, "smooth", ("smooth", "fade", "smooth", "fade", "slidefade", "fade"), 20),
    "dynamic": (230, "pop", ("pop", "slide", "smooth", "fade", "slide", "slidevert"), 37),
    "minimal": (150, "linear", ("fade", "fade", "off", "off", "fade", "fade"), 12),
    "cinematic": (520, "smooth", ("zoom", "fade", "smooth", "fade", "slidefadevert", "slidefade"), 45),
    "violet-abyss": (310, "abyss", ("scale", "scale", "smooth", "fade", "slidefade", "slidefadevert"), 24),
}
MATCHES = ("class", "initial_class")
RULE_STYLES = ("fade", "scale", "slide", "off")
HEADER = "-- MYO window animation settings: "


def preset(name):
    duration, curve, styles, strength = PRESETS[name]
    effects = {
        leaf: dict(style=style, duration=duration, curve=curve, strength=strength, direction="auto")
        for leaf, style in zip(LEAVES, styles)
    }
    if name == "classic":
        effects["workspace"]["strength"] = 100
        effects["focus"]["strength"] = 0
    rules = []
    if name == "violet-abyss":
        effects["open"].update(strength=14)
        effects["close"].update(duration=195, strength=9, curve="smooth")
        effects["move"].update(duration=220, animate_manual_resizes=True, animate_mouse_windowdragging=False)
        effects["focus"].update(duration=180, strength=0)
        effects["workspace"].update(duration=330, strength=30)
        rules = [
            dict(match="initial_class", value="kitty", style="scale"),
            dict(match="initial_class", value="org.freedesktop.impl.portal.desktop.hyprland", style="fade"),
        ]
    return dict(preset=name, effects=effects, rules=rules)


def integer(value, low, high):
    return type(value) is int and low <= value <= high


def validate(data):
    if data is None:
        return None
    if not isinstance(data, dict) or data.get("preset") not in (*PRESETS, "custom", "default"):
        raise ValueError("Invalid animation profile")
    effects, rules = data.get("effects"), data.get("rules")
    expected_leaves = set() if data["preset"] == "default" else set(LEAVES)
    if not isinstance(effects, dict) or set(effects) != expected_leaves or not isinstance(rules, list) or len(rules) > 100:
        raise ValueError("Invalid animation effects or rules")
    clean_effects, clean_rules = {}, []
    for leaf, effect in effects.items():
        if not isinstance(effect, dict) or effect.get("style") not in STYLES[leaf] or effect.get("curve") not in CURVES:
            raise ValueError(f"Invalid animation effect for {leaf}")
        if not integer(effect.get("duration"), 50, 2000) or not integer(effect.get("strength"), 0, 100):
            raise ValueError(f"Invalid duration or intensity for {leaf}")
        if effect.get("direction") not in SIDES:
            raise ValueError(f"Invalid direction for {leaf}")
        clean_effects[leaf] = {key: effect[key] for key in ("style", "duration", "curve", "strength", "direction")}
        if leaf == "move":
            for option in MOVE_OPTIONS:
                if option in effect:
                    if type(effect[option]) is not bool:
                        raise ValueError(f"Invalid value for {option}")
                    clean_effects[leaf][option] = effect[option]
    seen = set()
    for rule in rules:
        if not isinstance(rule, dict) or rule.get("match") not in MATCHES or rule.get("style") not in RULE_STYLES:
            raise ValueError("Invalid application rule")
        value = rule.get("value")
        if not isinstance(value, str) or not 0 < len(value) <= 200 or not value.isprintable():
            raise ValueError("Enter a valid window class")
        key = (rule["match"], value)
        if key in seen:
            raise ValueError(f"Duplicate application rule: {value}")
        seen.add(key)
        clean_rules.append(dict(match=key[0], value=value, style=rule["style"]))
    return dict(preset=data["preset"], effects=clean_effects, rules=clean_rules)


def quote(value):
    # Generated Lua strings only receive printable text. JSON escaping of
    # quotes and backslashes is also valid for these Lua strings.
    return json.dumps(value, ensure_ascii=False)


def style_for(effect):
    style = effect["style"]
    if style == "fade":
        return "popin 100%"
    if style == "slide":
        return "slide" if effect["direction"] == "auto" else "slide " + effect["direction"]
    return f'popin {100 - effect["strength"]}%'


def generate(profile):
    metadata = json.dumps(profile, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    revision = hashlib.sha256(metadata.encode()).hexdigest()
    lines = [HEADER + metadata]
    if profile is not None and profile["effects"]:
        for name, ((x1, y1), (x2, y2)) in CURVES.items():
            if name == "abyss" and not any(e["curve"] == name for e in profile["effects"].values()):
                continue
            lines.append(f'hl.curve("myo_{name}", {{ type = "bezier", points = {{ {{{x1}, {y1}}}, {{{x2}, {y2}}} }} }})')

        def animation(leaf, effect, style=None, enabled=True):
            if not enabled or effect["style"] == "off":
                lines.append(f'hl.animation({{ leaf = "{leaf}", enabled = false }})')
                return
            speed = effect["duration"] / 100
            curve = "pop" if effect["style"] == "pop" and effect["curve"] == "classic" else effect["curve"]
            suffix = f", style = {quote(style)}" if style else ""
            lines.append(f'hl.animation({{ leaf = "{leaf}", enabled = true, speed = {speed:g}, bezier = "myo_{curve}"{suffix} }})')

        effects = profile["effects"]
        for key, direction in (("open", "In"), ("close", "Out")):
            effect = effects[key]
            animation("windows" + direction, effect, style_for(effect))
            animation("fade" + direction, effect)
        animation("windowsMove", effects["move"])
        move_options = [
            f"{option} = {quote(effects['move'][option])}"
            for option in MOVE_OPTIONS if option in effects["move"]
        ]
        if move_options:
            lines.append("hl.config({ misc = { " + ", ".join(move_options) + " } })")
        animation("fadeSwitch", effects["focus"])
        if effects["focus"]["style"] != "off" and effects["focus"]["strength"]:
            opacity = 1 - min(effects["focus"]["strength"], 75) / 100
            lines.append(f"hl.config({{ decoration = {{ inactive_opacity = {opacity:g} }} }})")
        workspace = effects["workspace"]
        style = workspace["style"]
        if style.startswith("slide"):
            style += f' {workspace["strength"]}%'
        animation("workspaces", workspace, style)
        for direction in ("In", "Out"):
            special = effects["special"]
            style = special["style"]
            if style.startswith("slide"):
                style += f' {special["strength"]}%'
            animation("specialWorkspace" + direction, special, style)
    if profile is not None:
        if profile["preset"] == "violet-abyss":
            for direction in ("In", "Out"):
                effect = effects["open" if direction == "In" else "close"]
                animation("layers" + direction, effect, "fade")
                animation("fadeLayers" + direction, effect)
            lines.append('hl.layer_rule({ match = { namespace = "^qs-applauncher$" }, animation = "popin 94%" })')
            lines.append('hl.window_rule({ match = { float = true }, animation = "popin 90%" })')
        for rule in profile["rules"]:
            pattern = "^" + re.sub(r'([\\.^$|?*+()\[\]{}])', r'\\\1', rule["value"]) + "$"
            style = {"scale": "popin 80%", "fade": "popin 100%", "slide": "slide"}.get(rule["style"])
            override = f"animation = {quote(style)}" if style else "no_anim = true"
            lines.append(f'hl.window_rule({{ match = {{ {rule["match"]} = {quote(pattern)} }}, {override} }})')
    lines.append(f"serpantinumAnimationRevision = {quote(revision)}")
    return "\n".join(lines) + "\n", revision


def hyprctl(*args):
    result = subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=5)
    if result.returncode:
        raise RuntimeError((result.stderr or result.stdout).strip() or "hyprctl failed")
    return result.stdout.strip()


def require_revision(revision):
    response = hyprctl("eval", f"assert(serpantinumAnimationRevision == {quote(revision)}, 'MYO animation module did not load')")
    if response != "ok":
        raise RuntimeError(response or "MYO animation module did not load")


def check_integration(revision):
    try:
        require_revision(revision)
    except (RuntimeError, OSError, subprocess.SubprocessError) as exc:
        raise RuntimeError(
            "Reload the MYO Hyprland configuration with the animation loader "
            "from compositors/hyprland/hyprland.lua. "
            f"Hyprland returned: {exc}"
        ) from exc


def read_profile(path):
    if path.is_symlink():
        raise RuntimeError(f"Linked animation file was kept: {path}")
    if not path.exists():
        return None, "default"
    current = path.read_text(encoding="utf-8")
    header = current.split("\n", 1)[0]
    if header.startswith(HEADER):
        profile = validate(json.loads(header[len(HEADER):]))
        generated, revision = generate(profile)
        if current == generated:
            return profile, revision
    raise RuntimeError(f"Custom animation file was kept: {path}")


def atomic_write(path, text):
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(text)
            stream.close()
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


@contextlib.contextmanager
def profile_lock(path):
    import fcntl

    if not path.parent.is_dir():
        raise RuntimeError("Install the MYO Hyprland configuration before applying animations")
    lock_path = path.with_suffix(".lock")
    fd = os.open(lock_path, os.O_CREAT | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


def reload_profile(revision):
    if hyprctl("reload") != "ok":
        raise RuntimeError("Hyprland did not acknowledge reload")
    for attempt in range(10):
        try:
            require_revision(revision)
            break
        except RuntimeError:
            if attempt == 9:
                raise
            time.sleep(0.1)
    errors = hyprctl("configerrors")
    if errors:
        raise RuntimeError(errors)


def apply(path, profile):
    with profile_lock(path):
        _, previous_revision = read_profile(path)
        check_integration(previous_revision)
        errors = hyprctl("configerrors")
        if errors:
            raise RuntimeError(errors)
        previous = path.read_text(encoding="utf-8") if path.exists() else None
        generated, revision = generate(profile)
        try:
            atomic_write(path, generated)
            if hyprctl("reload") != "ok":
                raise RuntimeError("Hyprland did not acknowledge reload")
            for attempt in range(10):
                try:
                    require_revision(revision)
                    break
                except RuntimeError:
                    if attempt == 9:
                        raise
                    time.sleep(0.1)
            errors = hyprctl("configerrors")
            if errors:
                raise RuntimeError(errors)
        except (OSError, RuntimeError, subprocess.SubprocessError):
            if previous is None:
                path.unlink(missing_ok=True)
            else:
                atomic_write(path, previous)
            with contextlib.suppress(OSError, RuntimeError, subprocess.SubprocessError):
                hyprctl("reload")
            raise


def main():
    config = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    path = config / "hypr" / "serpantinum-animations.lua"
    command = sys.argv[1]
    if command == "load":
        profile, revision = read_profile(path)
        integration_error = None
        if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
            try:
                check_integration(revision)
            except RuntimeError as exc:
                integration_error = str(exc)
        result = dict(current=profile, presets={name: preset(name) for name in PRESETS}, revision=revision,
                      styles=STYLES, curves=list(CURVES), sides=SIDES, matches=MATCHES, ruleStyles=RULE_STYLES,
                      integrationError=integration_error)
    elif command == "clients":
        result = json.loads(hyprctl("-j", "clients"))
    elif command == "apply":
        profile = validate(json.loads(sys.argv[2]))
        # Quickshell can terminate the worker while restarting. Let apply()
        # restore the previous module if it has already replaced the file.
        def interrupted(signum, frame):
            raise InterruptedError("Animation update interrupted")

        signal.signal(signal.SIGTERM, interrupted)
        apply(path, profile)
        result = dict(current=profile)
    else:
        raise ValueError("Unknown animation command")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, RuntimeError, subprocess.SubprocessError) as exc:
        sys.exit(str(exc))
