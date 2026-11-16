"""Private per-user SQLite conversation store."""

from contextlib import closing
import json
import os
from pathlib import Path
import re
import sqlite3
import stat

from providers import ProviderError


def history_path():
    state = Path(os.environ.get("XDG_STATE_HOME") or (Path.home() / ".local/state"))
    return state / "serpantinum" / "ai" / "conversations.sqlite3"


def conversation_id(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-z-]{1,80}", value):
        raise ProviderError("invalid_request")
    return value


def open_private_db(path, create):
    if path.is_symlink() or path.parent.is_symlink():
        raise ProviderError("history_error")
    if create:
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not path.parent.exists():
        return None
    directory = path.parent.stat()
    if os.name == "posix" and (directory.st_uid != os.getuid() or directory.st_mode & 0o077):
        raise ProviderError("history_error")
    if create:
        try:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        except FileExistsError:
            pass
        else:
            os.close(fd)
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    if not stat.S_ISREG(info.st_mode) or (os.name == "posix" and (info.st_uid != os.getuid() or info.st_mode & 0o077)):
        raise ProviderError("history_error")
    return sqlite3.connect(path.absolute().as_uri() + "?mode=rw", uri=True, timeout=2)


def run_history(request, command):
    op = command["op"]
    snapshot = command.get("conversation")
    if op == "history_save":
        if not isinstance(snapshot, dict) or not isinstance(snapshot.get("messages"), list):
            raise ProviderError("invalid_request")
        key = conversation_id(snapshot.get("id"))
        updated = snapshot.get("updatedAt")
        body = json.dumps(snapshot, ensure_ascii=False)
        if type(updated) is not int or not 0 <= updated < 2**53 or len(body.encode("utf-8")) > 850_000:
            raise ProviderError("invalid_request")
    elif op == "history_delete":
        key = conversation_id(command.get("conversationId"))

    try:
        connection = open_private_db(history_path(), create=op == "history_save")
        if connection is None:
            return {}
        with closing(connection), connection:
            if op != "history_load":
                connection.execute("PRAGMA secure_delete=ON")
            version = connection.execute("PRAGMA user_version").fetchone()[0]
            if version == 0:
                if op != "history_save":
                    return {}
                connection.execute("BEGIN IMMEDIATE")
                connection.execute(
                    "CREATE TABLE IF NOT EXISTS conversations (id TEXT PRIMARY KEY, updated INTEGER NOT NULL, body TEXT NOT NULL)"
                )
                connection.execute("PRAGMA user_version=1")
            elif version != 1:
                raise ProviderError("history_error")
            if op == "history_load":
                for (record,) in connection.execute("SELECT body FROM conversations ORDER BY updated DESC"):
                    request.history_item(json.loads(record))
            elif op == "history_save":
                connection.execute(
                    "INSERT INTO conversations VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE "
                    "SET updated=excluded.updated, body=excluded.body WHERE excluded.updated >= conversations.updated",
                    (key, updated, body),
                )
            elif op == "history_delete":
                connection.execute("DELETE FROM conversations WHERE id=?", (key,))
            else:
                connection.execute("DELETE FROM conversations")
    except (OSError, sqlite3.Error, ValueError):
        raise ProviderError("history_error") from None
    return {}
