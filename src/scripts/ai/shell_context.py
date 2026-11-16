"""Select checked shell references and read the RAM sample only when requested."""

from pathlib import Path
import re


# Navigation keys match guide/GuidePopup.qml. Shortcuts are shipped Hyprland defaults.
TOPICS = (
    (
        re.compile(r"wallpaper\s*hub|search\s+wallpapers?|wallpapers?|\bобо(?:и|ев|ями|ях)\b", re.I),
        "Wallpaper Hub searches and previews wallpapers. Open Super+H → Search Wallpapers (Поиск обоев), "
        "or run `serpantinum settings wallpaper_search`. Search by text, then select a result to preview, download "
        "or apply. Super+W opens the separate wallpaper picker.",
    ),
    (
        re.compile(r"\b(?:themes?|appearance|themess|тем[ауые]|темой|оформлени\w*|палитр\w*)\b", re.I),
        "For color themes, open Super+H → Theme → Appearance (Тема → Оформление), and select a preset. "
        "The equivalent navigation command is `serpantinum settings theme theme_appearance`. "
        "For full desktop configuration packages, open Themess via `serpantinum settings themess`, preview a package and choose Apply.",
    ),
    (
        re.compile(r"\b(?:widgets?|виджет\w*)\b", re.I),
        "Widget settings are at Super+H → Display → Widgets (Экран → Виджеты). "
        "Open them directly with `serpantinum settings display display_widgets`. This page manages widgets by monitor.",
    ),
    (
        re.compile(r"\b(?:work\s?spaces?|рабоч\w*\s+пространств\w*)\b", re.I),
        "The shipped Hyprland bindings use Super+Left/Right to switch to the previous/next workspace on the current output. "
        "Super+1 through Super+0 select numbered slots, and Super+Shift+number moves the active window to a slot. "
        "Use `serpantinum msg workspace 2` to select slot 2. The bar also lets the user pick a slot.",
    ),
    (
        re.compile(r"\b(?:serpantinum|серпантинум)\b", re.I),
        "Serpantinum is the desktop shell. Super+H opens its settings. "
        "Its local AI chat opens via Super+H → AI → Open chat or `serpantinum msg open ai`.",
    ),
)
MEMORY = re.compile(
    r"\b(?:ram|system memory|memory usage|how much memory|озу|оперативн\w*\s+памят\w*)\b", re.I
)
MEASUREMENT = re.compile(
    r"\b(?:usage|used|using|current(?:ly)?|available|total|show|how much|"
    r"использ\w*|занят\w*|доступн\w*|всего|загруж\w*|покаж\w*|сколько|текущ\w*|сейчас)\b", re.I
)
GUIDANCE = re.compile(r"\b(?:how (?:to|do i|can i) (?:check|see)|как (?:посмотреть|узнать|проверить))\b", re.I)


def memory_snapshot(path=Path("/proc/meminfo")):
    """Use the kernel counters and used-memory formula used by Serpantinum's monitor."""
    try:
        text = path.read_text(encoding="ascii")
    except (OSError, UnicodeError):
        return None

    total = re.search(r"^MemTotal:[ \t]+(\d+)[ \t]+kB[ \t]*$", text, re.M)
    available = re.search(r"^MemAvailable:[ \t]+(\d+)[ \t]+kB[ \t]*$", text, re.M)
    if not total or not available:
        return None
    total_kib, available_kib = int(total[1]), int(available[1])
    if total_kib <= 0 or not 0 <= available_kib <= total_kib:
        return None
    used_kib = total_kib - available_kib
    return {
        "usedGiB": round(used_kib / 1048576, 2),
        "totalGiB": round(total_kib / 1048576, 2),
        "availableGiB": round(available_kib / 1048576, 2),
        "percent": used_kib * 100 // total_kib,
    }


def shell_context(messages):
    prompt = next((message["content"] for message in reversed(messages) if message["role"] == "user"), "")
    references = [reference for pattern, reference in TOPICS if pattern.search(prompt)]
    facts = {}
    if MEMORY.search(prompt):
        references.append("Super+B opens the system panel. The Process Explorer opens with Super+Shift+P.")
        if MEASUREMENT.search(prompt) and not GUIDANCE.search(prompt):
            memory = memory_snapshot()
            facts["memory"] = {"status": "available", **memory} if memory is not None else {"status": "unavailable"}
            if memory is None:
                references.append("The current RAM measurement is unavailable. Report it as unavailable and do not infer a number.")
            else:
                references.append(
                    f"RAM sampled for this request: {memory['usedGiB']} GiB used out of {memory['totalGiB']} GiB "
                    f"({memory['percent']}% used), {memory['availableGiB']} GiB available."
                )
    instructions = (
        "When answering about Serpantinum, treat the references below as facts for this request. "
        "Answer in the user's language. Shortcuts refer to shipped Hyprland defaults. "
        "Give navigation steps or commands the user can run. You cannot open panels or change settings. "
        "Do not claim that you performed an action. Report a current system reading only if it is supplied "
        "for this request. If it is missing or unavailable, say so."
    )
    if references:
        instructions += "\n\nRelevant shell references:\n- " + "\n- ".join(references)
    return instructions, facts
