"""Data-only schema for Themess v1. Package objects are validated before merging."""
import re

COLORS = """crust mantle base surface0 surface1 surface2 overlay0 overlay1 overlay2
subtext0 subtext1 text blue sapphire mauve teal green yellow peach red maroon pink""".split()
POSITIONS = "top bottom left right".split()
ANCHORS = [f"{v} {h}" for v in ("top", "bottom") for h in ("left", "center", "right")] + ["center"]


def number(low, high):
    return lambda value: type(value) in (int, float) and low <= value <= high


def integer(low, high):
    return lambda value: type(value) is int and low <= value <= high


def pattern(expr):
    return lambda value: isinstance(value, str) and re.fullmatch(expr, value) is not None


def choice(values):
    return lambda value: isinstance(value, str) and value in values


def items(rule, limit=32):
    return lambda value: isinstance(value, list) and len(value) <= limit and all(rule(item) for item in value)


def plain(value):
    return isinstance(value, str) and 0 < len(value) <= 80 and all(char.isprintable() for char in value)


BOOL = lambda value: type(value) is bool
PERCENT = integer(0, 100)
COLOR = pattern(r"#[a-fA-F0-9]{6}")
IDENTIFIER = pattern(r"[A-Za-z0-9_-]{1,80}")


VPN_THEMES = ("obsidian_glass", "liquid_noir", "midnight_blue", "graphite", "soft_neon", "pure_minimal")
UNIT = number(0, 1)
VPN_STYLE = {
    "material": choice(("matte", "glass", "liquid", "obsidian", "minimal", "neon")),
    "layout": choice(("auto", "centered", "vertical", "horizontal", "compact", "expanded")),
    "lineStyle": choice(("straight", "curved", "circuit", "flow", "minimal")),
    "buttonShape": choice(("circle", "squircle", "pill")),
    "typography": choice(("light", "regular", "bold")),
    **dict.fromkeys(("background", "button", "line", "active", "inactive", "text", "glowColor", "border"), COLOR),
    "opacity": UNIT, "blur": UNIT, "borderOpacity": UNIT, "glow": UNIT,
    "lineWidth": number(0.5, 6), "animSpeed": number(0.25, 3), "animate": BOOL, "radius": integer(0, 40),
}


FASTFETCH_THEMES = ("obsidian", "glass_noir", "minimal", "liquid_shadow", "terminal_classic", "floating_media",
                    "mochi", "overdrive")


def validate(value, schema, label, allow_empty=False):
    if not isinstance(schema, dict):
        if not schema(value):
            raise ValueError(f"{label}: invalid or unsupported value")
        return value
    if not isinstance(value, dict) or (not value and not allow_empty):
        raise ValueError(f"{label}: expected a non-empty object")
    for key, item in value.items():
        if key not in schema:
            raise ValueError(f"{label}.{key}: unsupported setting")
        validate(item, schema[key], f"{label}.{key}")
    return value


SETTINGS = {
    "palette": ("theme", {
        "mode": choice(("dark", "light")),
        "colors": dict.fromkeys(COLORS, COLOR),
    }),
    "materials": ("theme", {
        "borderRadius": integer(0, 64), "elementOpacity": PERCENT, "fontFamily": plain,
        "blurBackground": BOOL, "blurStyle": choice(("blur", "liquid")),
    }),
    "panels": ("bar", {
        "position": choice(POSITIONS), "style": choice(("modular", "solid", "fill")),
        "width": integer(10, 100), "height": integer(16, 128),
        "autohide": BOOL, "distinctPills": BOOL, "centerByEdges": BOOL, "timeShowDate": BOOL,
        "wifiShowName": BOOL,
        "sysmonStats": items(choice(("cpu", "ram", "temp"))),
    }),
    "animations": ("wallpaperTransition", {
        "mode": choice(("random", "custom")),
        "pool": items(choice(("fade", "wipe", "circle", "swipe", "paint")), 5),
        "effects": {
            "fade": {"duration": integer(100, 10000)},
            "wipe": {"duration": integer(100, 10000), "orientation": choice(("random", "horizontal", "vertical"))},
            "circle": {"duration": integer(100, 10000), "origin": choice(("random", "center"))},
            "swipe": {"duration": integer(100, 10000), "direction": choice(
                ("left", "right", "top", "bottom", "top_left", "top_right", "bottom_left", "bottom_right"))},
            "paint": {"duration": integer(100, 10000)},
        },
    }),
    "canvas": ("canvas", {
        "enabled": BOOL, "sensitivity": number(0.2, 5), "inertia": BOOL, "friction": number(1, 20),
        "wheelAction": choice(("zoom", "pan", "none")), "zoomStep": number(1.02, 1.5),
        "gridSize": integer(4, 400), "snapToGrid": BOOL, "snapToGuides": BOOL, "dragToPan": BOOL,
        "minimap": choice(("auto", "always", "never")),
        "minimapCorner": choice(("top-left", "top-right", "bottom-left", "bottom-right")),
    }),
    "dock": ("dock", {
        "enabled": BOOL, "position": choice(POSITIONS), "onTop": BOOL, "background": BOOL,
        "floating": BOOL, "exclusive": BOOL, "elementSize": integer(16, 128),
        "autohide": BOOL, "smartAutohide": BOOL, "autohideTimeout": integer(0, 10000),
        "hoverScale": integer(100, 200), "showRunningApps": BOOL, "showRunningIndicators": BOOL,
    }),
    "launcher": ("launcher", {
        "position": choice(POSITIONS + ["center"]), "width": integer(250, 1600),
        "itemCount": integer(1, 20), "smartRanking": BOOL,
    }),
    "notifications": ("notifications", {
        "dnd": BOOL, "position": choice(ANCHORS + ["custom"]), "horizontalPosition": PERCENT,
        "verticalPosition": PERCENT, "sound": BOOL, "showEmptyGraphic": BOOL, "rightClickClose": BOOL,
    }),
    # Look of the VPN panel only (singletons/theme/VpnAppearance.qml). No subscription, link,
    # server or token can be expressed here, and the user's own saved presets ("presets")
    # are not part of the schema, so a package can neither carry them nor overwrite them.
    "vpn": ("vpnAppearance", {
        "theme": choice(VPN_THEMES + ("custom",)),
        "custom": VPN_STYLE,
    }),
    # Fastfetch Media look and playback. The media file itself is the separate
    # `fastfetchMedia` component (validated like a wallpaper); a package never names a path
    # here, and it cannot turn the clip's sound on (playAudio is not part of the schema).
    "fastfetch": ("fastfetchMedia", {
        "appearance": {
            "theme": choice(FASTFETCH_THEMES),
            "layout": choice(("classic", "wide", "vertical", "floating", "minimal")),
            "position": choice(("start", "center", "end")),
            "width": integer(15, 100), "height": integer(15, 100),
            "zoom": number(0.5, 2), "opacity": UNIT, "radius": integer(0, 40),
        },
        "loop": BOOL, "autoplay": BOOL, "pauseWhenHidden": BOOL,
        "speed": number(0.25, 2), "animationFps": integer(0, 60),
    }),
    # Atelier widget looks: how much optional motion they show.
    "studio": ("widgetStudio", {
        "motion": choice(("full", "reduced", "off")),
    }),
}

# Widget fields a package may set besides id/type/variant/geometry. Appearance only:
# no command, no host to ping, no path. Terminal modes that would run a configured
# command ("monitor") are not accepted.
ATELIER_STYLES = ("matte", "premium", "minimal", "retro", "elegant", "editorial", "technical", "borderless", "compact")
WIDGET_FIELDS = {
    "faceStyle": choice(ATELIER_STYLES),
    "onlyWhilePlaying": BOOL,
    "showTotals": BOOL,
}
TERMINAL_FIELDS = {
    "mode": choice(("interactive", "fastfetch", "fetchShell", "cmatrix")),
    "shell": choice(("auto", "bash", "zsh")),
    "fontFamily": plain, "fontSize": integer(7, 32),
    "colorScheme": choice(("theme", "classic", "matrix", "cyber", "amber")),
    "backgroundOpacity": UNIT, "cornerRadius": integer(0, 40),
    "appearAnimation": choice(("fade", "slide", "scale", "none")),
}


def configuration(kind, value, caps, name):
    section, schema = SETTINGS[kind]
    if isinstance(value, dict) and set(value) == {section}:
        value = value[section]
    if kind == "vpn" and isinstance(value, dict) and value and set(value) <= set(VPN_STYLE):
        value = {"theme": "custom", "custom": value}         # a bare style object is a custom look
    if kind == "panels":
        modules = choice(caps.get("barModules", []))
        group = items(lambda item: modules(item) or (
            isinstance(item, list) and bool(item) and items(modules)(item)))
        schema = dict(schema, modules=dict.fromkeys(("left", "center", "right"), group),
                      menuItems=items(choice(caps.get("barMenu", []))),
                      workspacesStyle=choice(caps.get("workspacesStyles", [])),
                      timeStyle=choice(caps.get("timeStyles", [])),
                      sysmonStyle=choice(("wave", "bars")))
    value = validate(value, schema, kind)
    if kind == "palette":
        if not value.get("colors"):
            raise ValueError("palette.colors: missing colors")
        value = dict(value, matugen=False, activePreset=name)
    if kind == "animations" and value.get("pool") == []:
        raise ValueError("animations.pool: select at least one effect")
    return section, value


def widget_layout(value, caps):
    if isinstance(value, dict) and set(value) <= {"name", "widgets"}:
        value = value.get("widgets")
    if not isinstance(value, list) or len(value) > 100:
        raise ValueError("widgets: expected an array with at most 100 widgets")
    types = caps.get("widgetTypes", {})
    result = []
    ids = set()
    for index, item in enumerate(value):
        label = f"widgets[{index}]"
        schema = {
            "id": IDENTIFIER, "type": choice(types),
            "anchor": choice(ANCHORS), "x": number(-50000, 50000), "y": number(-50000, 50000),
            "w": number(16, 8192), "h": number(16, 8192), "wOpacity": number(0, 1),
            "rotation": number(0, 360), "stretchWidth": BOOL, "stretchHeight": BOOL,
        }
        if isinstance(item, dict) and schema["type"](item.get("type")):
            schema["variant"] = choice(types[item["type"]])
            schema.update(WIDGET_FIELDS)
            if item["type"] == "terminal":
                schema.update(TERMINAL_FIELDS)
            if item["type"] == "music":
                # Appearance only. Themes cannot apply EQ, presets, routing or commands.
                schema.update(musicDrawer=BOOL, musicAnimations=BOOL, musicVisualizer=BOOL,
                              musicMaterial=choice(("liquid", "mica", "neon", "minimal")))
        validate(item, schema, label)
        if not {"id", "type", "x", "y", "w", "h"} <= item.keys():
            raise ValueError(f"{label}: requires id, type, x, y, w and h")
        if item["type"] == "image":
            raise ValueError(f"{label}: external image widget paths are unavailable in v1")
        if item["id"] in ids:
            raise ValueError(f"{label}: duplicate widget id")
        ids.add(item["id"])
        fields = {"id": "wId", "type": "wType", "variant": "wVariant", "x": "wX",
                  "y": "wY", "w": "wWidth", "h": "wHeight", "rotation": "wRotation"}
        result.append({fields.get(key, key): value for key, value in item.items()})
    return result
