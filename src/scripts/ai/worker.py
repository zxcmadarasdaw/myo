"""Serpantinum AI worker. Commands and events are UTF-8 JSON Lines over stdio."""

import json
import os
from pathlib import Path
import socket
import stat
import sys
import tempfile
import threading

from providers import ProviderError, ProviderManager
from history import run_history
from shell_context import shell_context
from actions import parse_proposal, proposal_instructions, run_action_log


MAX_INPUT = 1024 * 1024
MAX_INSTRUCTIONS = 16 * 1024
MAX_JOBS = 4
HISTORY_OPS = ("history_load", "history_save", "history_delete", "history_clear")
ACTION_OPS = ("action_begin", "action_finish", "action_list")


class Request:
    def __init__(self, request_id, emit, timeout, idle_timeout):
        self.id = request_id
        self.emit = emit
        self.timeout = timeout
        self.idle_timeout = idle_timeout
        self.lock = threading.Lock()
        self.done = False
        self.socket = None
        self.proposal_tail = None

    def attach_socket(self, connection):
        with self.lock:
            if self.done:
                raise ProviderError("cancelled")
            self.socket = connection

    def delta(self, text):
        with self.lock:
            if not self.done:
                if self.proposal_tail is not None:
                    self.proposal_tail = (self.proposal_tail + text)[-1024:]
                self.emit(self.id, "delta", text=text)

    def history_item(self, conversation):
        with self.lock:
            if self.done:
                raise ProviderError("cancelled")
            self.emit(self.id, "history_item", conversation=conversation)

    def system_facts(self, facts):
        with self.lock:
            if not self.done:
                self.emit(self.id, "system_facts", **facts)

    def finish(self, event, **data):
        with self.lock:
            if self.done:
                return
            self.done = True
            self.emit(self.id, event, **data)
            if event in ("cancelled", "error") and self.socket is not None:
                try:
                    self.socket.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass


class ModelRegistry:
    def refresh(self, provider, request, probe=False):
        models = provider.probe(request) if probe else provider.list_models(request)
        return {model["id"]: model for model in models}



def instructions_path():
    config = Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config"))
    return config / "serpantinum" / "ai" / "instructions.txt"


def load_instructions():
    path = instructions_path()
    try:
        if path.parent.is_symlink():
            raise ProviderError("storage_error")
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    except FileNotFoundError:
        return ""
    with os.fdopen(fd, "rb") as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or (os.name == "posix" and (info.st_uid != os.getuid() or info.st_mode & 0o077)):
            raise ProviderError("storage_error")
        raw = source.read(MAX_INSTRUCTIONS + 1)
    if len(raw) > MAX_INSTRUCTIONS:
        raise ProviderError("storage_error")
    return raw.decode("utf-8")


def save_instructions(value):
    if not isinstance(value, str) or len(value.encode("utf-8")) > MAX_INSTRUCTIONS:
        raise ProviderError("invalid_request")
    path = instructions_path()
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.parent.is_symlink() or (
        os.name == "posix" and (path.parent.stat().st_uid != os.getuid() or path.parent.stat().st_mode & 0o077)
    ):
        raise ProviderError("storage_error")
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
            temporary_path = Path(output.name)
            output.write(value.encode("utf-8"))
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary_path, path)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def generation_args(command):
    model = command.get("model")
    messages = command.get("messages")
    options = command.get("options", {})
    if (
        not isinstance(model, str) or not model or len(model) > 512
        or not isinstance(messages, list) or not 1 <= len(messages) <= 128
        or not isinstance(options, dict)
    ):
        raise ProviderError("invalid_request")
    normalized = []
    for message in messages:
        if (
            not isinstance(message, dict) or message.get("role") not in ("system", "user", "assistant")
            or not isinstance(message.get("content"), str)
        ):
            raise ProviderError("invalid_request")
        normalized.append({"role": message["role"], "content": message["content"]})
    temperature = options.get("temperature", 0.7)
    tokens = options.get("maxTokens", 2048)
    stream = options.get("stream", True)
    if (
        type(temperature) not in (float, int) or not 0 <= temperature <= 2
        or type(tokens) is not int or not 1 <= tokens <= 32768
        or type(stream) is not bool
    ):
        raise ProviderError("invalid_request")
    return model, normalized, {"temperature": temperature, "maxTokens": tokens, "stream": stream}


class Worker:
    def __init__(self):
        self.provider_manager = ProviderManager()
        self.models = ModelRegistry()
        self.jobs = {}
        self.jobs_lock = threading.Lock()
        self.output_lock = threading.Lock()

    def emit(self, request_id, event, **data):
        record = json.dumps({"id": request_id, "event": event, **data}, ensure_ascii=True)
        with self.output_lock:
            print(record, flush=True)

    def dispatch(self, command):
        if not isinstance(command, dict):
            return
        request_id, op = command.get("id"), command.get("op")
        if not isinstance(request_id, str) or not 1 <= len(request_id) <= 80:
            return
        with self.jobs_lock:
            current = self.jobs.get(request_id)
            if op != "cancel" and current is not None:
                return
            at_capacity = len(self.jobs) >= MAX_JOBS
        if op == "cancel":
            if current is not None:
                current.finish("cancelled")
            return
        if op not in ("probe", "models", "chat", "load_instructions", "save_instructions", *HISTORY_OPS, *ACTION_OPS):
            self.emit(request_id, "error", code="invalid_request")
            return
        if at_capacity:
            self.emit(request_id, "error", code="busy")
            return
        timeout = command.get("timeout", 180 if op == "chat" else 10)
        if type(timeout) not in (int, float) or not 0.1 <= timeout <= 600:
            self.emit(request_id, "error", code="invalid_request")
            return
        request = Request(request_id, self.emit, timeout, 45 if op == "chat" else 8)
        with self.jobs_lock:
            self.jobs[request_id] = request
        self.emit(request_id, "started")
        threading.Thread(target=self.run, args=(request, command), daemon=True).start()

    def run(self, request, command):
        timer = threading.Timer(request.timeout, request.finish, args=("error",), kwargs={"code": "timeout"})
        timer.daemon = True
        timer.start()
        try:
            request.finish("completed", **self.perform(request, command))
        except ProviderError as error:
            request.finish("error", code=error.code)
        except (OSError, UnicodeError):
            request.finish("error", code="storage_error")
        except Exception:
            request.finish("error", code="internal_error")
        finally:
            timer.cancel()
            with self.jobs_lock:
                self.jobs.pop(request.id, None)

    def perform(self, request, command):
        op = command["op"]
        if op in HISTORY_OPS:
            return run_history(request, command)
        if op in ACTION_OPS:
            return run_action_log(command)
        if op == "load_instructions":
            return {"text": load_instructions()}
        if op == "save_instructions":
            save_instructions(command.get("text"))
            return {}
        profile = command.get("profile", {"provider": "ollama"})
        provider = self.provider_manager.resolve(profile)
        if op in ("probe", "models"):
            models = self.models.refresh(provider, request, probe=op == "probe")
            return {"models": list(models.values())}
        model, messages, options = generation_args(command)
        if model not in self.models.refresh(provider, request):
            raise ProviderError("model_unavailable")
        context, facts = shell_context(messages)
        if command.get("proposeActions") is True:
            request.proposal_tail = ""
            context += "\n\n" + proposal_instructions()
        instructions = load_instructions()
        if instructions:
            context += "\n\nUser's instructions:\n" + instructions
        messages.insert(0, {"role": "system", "content": context})
        if facts:
            request.system_facts(facts)
        result = provider.chat(request, model, messages, options)
        if request.proposal_tail is not None:
            result.update(parse_proposal(request.proposal_tail))
        return result


def main():
    worker = Worker()
    while line := sys.stdin.buffer.readline(MAX_INPUT + 1):
        if len(line) > MAX_INPUT:
            return
        try:
            command = json.loads(line)
        except (ValueError, UnicodeError):
            continue
        worker.dispatch(command)


if __name__ == "__main__":
    main()
