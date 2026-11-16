"""Validate proposals and record approvals. This module never executes an action."""

from contextlib import closing
import json
from pathlib import Path
import re
import sqlite3
import time
from uuid import uuid4

from history import history_path, open_private_db
from providers import ProviderError


THEMES = ("Dracula", "Mocha", "Nord", "Tokyo")
TARGETLESS = ("open_settings", "open_wallpaper_hub", "show_system_info")
STATUS = ("applied", "requested", "failed", "stale", "undone")
ACTION_FENCE = re.compile(r"(?:^|\n)```serpantinum-action[ \t]*\r?\n([^\r\n]{1,500})\r?\n```[ \t]*\s*\Z")


def proposal_instructions():
    return (
        "For an explicit request to perform a supported desktop action, offer exactly one proposal. "
        "Explain it briefly in the user's language, then put a single compact JSON object on its own line "
        "inside a final ```serpantinum-action fenced block. A proposal requires local approval. "
        "Do not claim it was executed. For advice, explanations or unsupported actions, omit the block. "
        'Use {"id":"open_settings"}, {"id":"open_wallpaper_hub"}, {"id":"show_system_info"}, '
        '{"id":"switch_workspace","target":2}, {"id":"launch_app","target":"Firefox"}, '
        '{"id":"set_theme","target":"Tokyo"}. Use an unambiguous installed application name or desktop ID. '
        "Theme names: " + ", ".join(THEMES) + "."
    )


def validate_action(value):
    if not isinstance(value, dict) or not isinstance(value.get("id"), str):
        raise ProviderError("invalid_action")
    action_id = value["id"]
    if action_id in TARGETLESS and set(value) == {"id"}:
        return {"id": action_id}
    if set(value) != {"id", "target"}:
        raise ProviderError("invalid_action")
    target = value["target"]
    if (
        (action_id == "switch_workspace" and type(target) is int and 1 <= target <= 2147483647)
        or (action_id == "launch_app" and isinstance(target, str) and re.fullmatch(r"[\w .+()'&-]{1,100}", target.strip()))
        or (action_id == "set_theme" and isinstance(target, str) and target in THEMES)
    ):
        return {"id": action_id, "target": target.strip() if isinstance(target, str) else target}
    raise ProviderError("invalid_action")


def unique_object(pairs):
    result = dict(pairs)
    if len(result) != len(pairs):
        raise ValueError("duplicate action field")
    return result


def parse_proposal(tail):
    match = ACTION_FENCE.search(tail)
    if not match:
        return {}
    try:
        return {"actionProposal": validate_action(json.loads(match[1], object_pairs_hook=unique_object))}
    except (ValueError, ProviderError):
        return {"actionRejected": True}


def theme_colors(name):
    file = Path(__file__).resolve().parents[2] / "assets" / "themes" / (name + ".json")
    try:
        preset = json.loads(file.read_text(encoding="utf-8"))
        colors = preset["colors"]
    except (OSError, UnicodeError, ValueError, KeyError, TypeError):
        raise ProviderError("action_unavailable") from None
    if not isinstance(colors, dict) or not {"base", "text"} <= colors.keys() or not all(
        re.fullmatch(r"[A-Za-z][A-Za-z0-9]{0,30}", key)
        and isinstance(value, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", value)
        for key, value in colors.items()
    ):
        raise ProviderError("action_unavailable")
    return colors


def run_action_log(command):
    op = command["op"]
    if op == "action_begin":
        action = validate_action(command.get("action"))
        undo = command.get("undo", False)
        if type(undo) is not bool or (undo and action["id"] not in ("set_theme", "switch_workspace")):
            raise ProviderError("invalid_action")
        colors = theme_colors(action["target"]) if action["id"] == "set_theme" and not undo else None
        entry = {
            "recordId": uuid4().hex, "at": time.time_ns() // 1_000_000, **action,
            "undo": undo, "outcome": "confirmed",
        }
    elif op == "action_finish":
        record_id, outcome = command.get("recordId"), command.get("outcome")
        if not isinstance(record_id, str) or not re.fullmatch(r"[a-f0-9]{32}", record_id) or outcome not in STATUS:
            raise ProviderError("invalid_action")

    try:
        db = open_private_db(history_path().with_name("actions.sqlite3"), create=op == "action_begin")
        if db is None:
            if op == "action_list":
                return {"entries": []}
            raise ProviderError("action_log_error")
        with closing(db), db:
            if op == "action_begin":
                db.execute(
                    "CREATE TABLE IF NOT EXISTS actions (record_id TEXT PRIMARY KEY, at INTEGER NOT NULL, "
                    "body TEXT NOT NULL, outcome TEXT NOT NULL)"
                )
                db.execute("INSERT INTO actions VALUES (?, ?, ?, ?)",
                           (entry["recordId"], entry["at"], json.dumps(entry), "confirmed"))
                db.execute("DELETE FROM actions WHERE record_id IN "
                           "(SELECT record_id FROM actions ORDER BY at DESC, rowid DESC LIMIT -1 OFFSET 200)")
                return {"entry": entry, "colors": colors}
            if op == "action_finish":
                updated = db.execute("UPDATE actions SET outcome=? WHERE record_id=? AND outcome='confirmed'",
                                     (outcome, record_id))
                if not updated.rowcount and db.execute(
                    "SELECT outcome FROM actions WHERE record_id=?", (record_id,)
                ).fetchone() != (outcome,):
                    raise ProviderError("action_log_error")
                return {}
            if not db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='actions'").fetchone():
                return {"entries": []}
            return {"entries": [
                {**json.loads(body), "outcome": result}
                for body, result in db.execute("SELECT body, outcome FROM actions ORDER BY at DESC, rowid DESC LIMIT 80")
            ]}
    except (OSError, sqlite3.Error, ValueError, ProviderError):
        raise ProviderError("action_log_error") from None
