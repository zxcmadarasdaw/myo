"""Exercise the worker protocol against a loopback HTTP server."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
from queue import Queue
import socket
import subprocess
import sys
from tempfile import TemporaryDirectory
from threading import Event, Thread
import unittest
from unittest.mock import patch
from importlib.util import module_from_spec, spec_from_file_location


WORKER = Path(__file__).resolve().parents[2] / "src/scripts/ai/worker.py"
CONTEXT_SPEC = spec_from_file_location("shell_context", WORKER.with_name("shell_context.py"))
CONTEXT = module_from_spec(CONTEXT_SPEC)
CONTEXT_SPEC.loader.exec_module(CONTEXT)


class OllamaHandler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def reply(self, data, status=200):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path != "/api/tags":
            self.reply({}, 404)
        elif self.server.tags_error:
            self.reply(self.server.tags_error[1], self.server.tags_error[0])
        else:
            self.reply({"models": self.server.catalog})

    def do_POST(self):
        if self.path != "/api/chat":
            self.reply({}, 404)
            return
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.server.prompts.put((payload, self.headers.get("Authorization")))
        last = {"model": payload["model"], "message": {"content": self.server.reply_text}, "done": True, "eval_count": 1}
        if not payload["stream"]:
            self.reply(last)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.end_headers()
        self.wfile.write(b'{"message":{"content":"Hi "},"done":false}\n')
        self.wfile.flush()
        if self.server.pause_stream:
            self.server.release_stream.wait(5)
        try:
            self.wfile.write(json.dumps(last).encode("utf-8") + b"\n")
        except OSError:  # The worker can close the socket while a reply is pending.
            pass


class WorkerTest(unittest.TestCase):
    def setUp(self):
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), OllamaHandler)
        self.server.catalog = [
            {"model": "small:latest", "size": 500, "details": {"family": "small"}},
            {"model": "alias:latest", "remote_host": "https://example.org"},
            {"model": "model:cloud"},
        ]
        self.server.pause_stream = False
        self.server.reply_text = "Привет"
        self.server.release_stream = Event()
        self.server.tags_error = None
        self.server.prompts = Queue()
        self.profile = {"provider": "ollama", "baseUrl": f"http://127.0.0.1:{self.server.server_port}"}
        self.messages = [{"role": "user", "content": "ping"}]
        self.events = Queue()
        self.thread = Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.config = TemporaryDirectory()
        self.addCleanup(self.config.cleanup)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.addCleanup(self.server.release_stream.set)
        self.start_worker()
        self.addCleanup(self.stop_worker)

    def start_worker(self):
        environment = dict(os.environ, XDG_CONFIG_HOME=self.config.name, XDG_STATE_HOME=self.config.name)
        self.worker = subprocess.Popen(
            [sys.executable, str(WORKER)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, encoding="utf-8", env=environment,
        )
        self.reader = Thread(target=self.read_events, args=(self.worker.stdout,), daemon=True)
        self.reader.start()

    def read_events(self, stdout):
        for line in stdout:
            self.events.put(json.loads(line))

    def stop_worker(self):
        self.worker.stdin.close()
        if self.worker.poll() is None:
            self.worker.wait(timeout=5)
        self.reader.join(timeout=2)
        self.worker.stdout.close()
        diagnostics = self.worker.stderr.read()
        self.worker.stderr.close()
        self.assertEqual(diagnostics, "")

    def send(self, id, op, **kwargs):
        command = {"id": id, "op": op, "profile": self.profile, **kwargs}
        self.worker.stdin.write(json.dumps(command) + "\n")
        self.worker.stdin.flush()

    def collect(self, id, until=None):
        events = []
        while True:
            event = self.events.get(timeout=5)
            self.assertEqual(event["id"], id)
            events.append(event)
            if event["event"] in (until, "completed", "cancelled", "error"):
                return events

    def test_catalog_and_stream(self):
        self.send("probe", "probe")
        catalog = self.collect("probe")[-1]
        self.assertEqual(catalog["models"], [{"id": "small:latest", "name": "small:latest", "size": 500, "family": "small"}])
        self.send("chat", "chat", model="small:latest", messages=self.messages)
        events = self.collect("chat")
        self.assertEqual([event["event"] for event in events], ["started", "delta", "delta", "completed"])
        self.assertEqual("".join(event.get("text", "") for event in events), "Hi Привет")
        self.assertEqual(events[-1]["usage"], {"eval_count": 1})

        self.server.catalog.pop(0)
        self.send("chat2", "chat", model="small:latest", messages=self.messages)
        self.assertEqual(self.collect("chat2")[-1]["code"], "model_unavailable")

    def test_errors_and_empty_catalog(self):
        self.send("external", "probe", profile={"provider": "ollama", "baseUrl": "https://example.org"})
        self.assertEqual(self.collect("external")[-1]["code"], "invalid_url")
        self.send("unsupported", "probe", profile={"provider": "external"})
        self.assertEqual(self.collect("unsupported")[-1]["code"], "unsupported_provider")
        for status, body, code in ((200, {}, "invalid_response"), (401, {}, "authorization"), (429, {}, "rate_limit")):
            self.server.tags_error = (status, body)
            self.send("error", "models")
            self.assertEqual(self.collect("error")[-1]["code"], code)
        self.server.tags_error = None
        self.server.catalog = []
        self.send("empty", "probe")
        self.assertEqual(self.collect("empty")[-1]["models"], [])

    def test_unavailable_ollama_does_not_block_next_probe(self):
        with socket.socket() as not_listening:
            not_listening.bind(("127.0.0.1", 0))
            base_url = f"http://127.0.0.1:{not_listening.getsockname()[1]}"
            self.send("offline", "probe", profile={"provider": "ollama", "baseUrl": base_url}, timeout=4.5)
            self.assertEqual(self.collect("offline")[-1]["code"], "unavailable")
        self.send("online", "probe")
        self.assertEqual(self.collect("online")[-1]["event"], "completed")

    def test_cancel_and_deadline(self):
        self.server.pause_stream = True
        self.send("cancelled", "chat", model="small:latest", messages=self.messages)
        self.assertEqual(self.collect("cancelled", until="delta")[-1]["event"], "delta")
        self.send("cancelled", "cancel")
        self.assertEqual(self.collect("cancelled")[-1]["event"], "cancelled")
        self.send("timeout", "chat", model="small:latest", messages=self.messages, timeout=0.5)
        self.assertEqual(self.collect("timeout")[-1]["code"], "timeout")
        self.server.release_stream.set()
        self.send("probe", "probe")
        self.assertEqual(self.collect("probe")[-1]["event"], "completed")

    def test_private_instructions_and_nonstreaming_after_restart(self):
        self.send("save", "save_instructions", text="Private instruction")
        self.assertEqual(self.collect("save")[-1]["event"], "completed")
        path = Path(self.config.name) / "serpantinum/ai/instructions.txt"
        if os.name == "posix":
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
        self.stop_worker()
        self.start_worker()
        self.send("load", "load_instructions")
        self.assertEqual(self.collect("load")[-1]["text"], "Private instruction")
        self.send("chat", "chat", model="small:latest", messages=self.messages,
                  options={"temperature": 1.2, "maxTokens": 64, "stream": False})
        self.assertEqual(self.collect("chat")[-1]["event"], "completed")
        prompt, authorization = self.server.prompts.get(timeout=2)
        self.assertIsNone(authorization)
        self.assertEqual(prompt["messages"][0]["role"], "system")
        self.assertTrue(prompt["messages"][0]["content"].endswith("User's instructions:\nPrivate instruction"))
        self.assertEqual(prompt["stream"], False)
        self.assertEqual(prompt["options"], {"temperature": 1.2, "num_predict": 64})

    def test_history_load_before_opt_in_and_crud_across_restart(self):
        path = Path(self.config.name) / "serpantinum/ai/conversations.sqlite3"
        self.send("initial", "history_load")
        self.assertEqual([event["event"] for event in self.collect("initial")], ["started", "completed"])
        self.assertFalse(path.exists())

        first = {"id": "chat-one", "title": "Первый", "messages": [{"role": "user", "content": "Привет"}], "updatedAt": 10}
        second = {"id": "chat-two", "title": "Второй", "messages": [], "updatedAt": 20}
        for chat in (first, second, dict(first, title="older", updatedAt=5)):
            self.send("save-" + str(chat["updatedAt"]), "history_save", conversation=chat)
            self.assertEqual(self.collect("save-" + str(chat["updatedAt"]))[-1]["event"], "completed")
        if os.name == "posix":
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)

        self.stop_worker()
        self.start_worker()
        self.send("load", "history_load")
        self.assertEqual([event["conversation"] for event in self.collect("load") if event["event"] == "history_item"],
                         [second, first])

        self.send("delete", "history_delete", conversationId="chat-two")
        self.assertEqual(self.collect("delete")[-1]["event"], "completed")
        self.send("rest", "history_load")
        self.assertEqual([event["conversation"] for event in self.collect("rest") if event["event"] == "history_item"],
                         [first])
        self.send("clear", "history_clear")
        self.assertEqual(self.collect("clear")[-1]["event"], "completed")
        self.send("empty", "history_load")
        self.assertEqual([event["event"] for event in self.collect("empty")], ["started", "completed"])


    def test_shell_context_reaches_provider_without_actions(self):
        prompt_text = "Открой Wallpaper Hub и скажи, где настройки виджетов"
        self.send("context", "chat", model="small:latest", messages=[{"role": "user", "content": prompt_text}])
        events = self.collect("context")
        self.assertEqual([event["event"] for event in events], ["started", "delta", "delta", "completed"])
        payload, _ = self.server.prompts.get(timeout=2)
        context = payload["messages"][0]
        self.assertIn("serpantinum settings wallpaper_search", context["content"])
        self.assertIn("serpantinum settings display display_widgets", context["content"])
        self.assertIn("You cannot open panels or change settings", context["content"])
        self.assertEqual(payload["messages"][1], {"role": "user", "content": prompt_text})
        self.assertNotIn("tools", payload)

    def test_memory_request_reports_structured_facts(self):
        messages = [{"role": "user", "content": "Покажи использование оперативной памяти"}]
        self.send("ram", "chat", model="small:latest", messages=messages)
        events = self.collect("ram")
        self.assertEqual(events[1]["event"], "system_facts")
        memory = events[1]["memory"]
        payload, _ = self.server.prompts.get(timeout=2)
        context = payload["messages"][0]["content"]
        if memory["status"] == "available":
            self.assertIn(f"{memory['percent']}% used", context)
        else:
            self.assertEqual(memory, {"status": "unavailable"})
            self.assertIn("current RAM measurement is unavailable", context)


    def test_model_proposal_requires_opt_in_and_is_validated(self):
        marker = chr(96) * 3
        for index, body in enumerate((
            '{"id":"switch_workspace","target":2}',
            '{"id":"switch_workspace","target":"2"}',
            '{"id":"launch_app","target":"sh; other"}',
            '{"id":"open_settings","extra":true}',
            '{"id":"open_settings","id":"open_wallpaper_hub"}',
            '{"id":"execute_shell","target":"example"}',
        )):
            self.server.reply_text = f"Proposed action.\n{marker}serpantinum-action\n{body}\n{marker}"
            self.send("proposal", "chat", model="small:latest", messages=self.messages, proposeActions=True)
            result = self.collect("proposal")[-1]
            if index == 0:
                self.assertEqual(result["actionProposal"], {"id": "switch_workspace", "target": 2})
            else:
                self.assertTrue(result["actionRejected"])
            self.assertFalse((Path(self.config.name) / "serpantinum/ai/actions.sqlite3").exists())
            # No approval or journal write occurs on generation.
        self.send("off", "chat", model="small:latest", messages=self.messages)
        self.assertNotIn("actionRejected", self.collect("off")[-1])

    def test_action_log_and_bundled_theme(self):
        self.send("empty-actions", "action_list")
        self.assertEqual(self.collect("empty-actions")[-1]["entries"], [])
        path = Path(self.config.name) / "serpantinum/ai/actions.sqlite3"
        self.assertFalse(path.exists())
        self.send("wrong-theme", "action_begin", action={"id": "set_theme", "target": "../outside"})
        self.assertEqual(self.collect("wrong-theme")[-1]["code"], "invalid_action")
        for name in ("Dracula", "Mocha", "Nord", "Tokyo"):
            self.send("begin-" + name, "action_begin", action={"id": "set_theme", "target": name})
            result = self.collect("begin-" + name)[-1]
            self.assertEqual(result["event"], "completed", result)
            self.assertRegex(result["colors"]["base"], r"^#[0-9a-fA-F]{6}$")
            record_id = result["entry"]["recordId"]
            self.send("finish-" + name, "action_finish", recordId=record_id, outcome="applied")
            self.assertEqual(self.collect("finish-" + name)[-1]["event"], "completed")
        self.send("list", "action_list")
        entries = self.collect("list")[-1]["entries"]
        self.assertEqual([entry["target"] for entry in entries], ["Tokyo", "Nord", "Mocha", "Dracula"])
        self.assertTrue(all(entry["outcome"] == "applied" and "colors" not in entry for entry in entries))


class ShellContextTest(unittest.TestCase):
    def test_routes_for_supported_questions(self):
        cases = {
            "Как поменять тему?": "serpantinum settings theme theme_appearance",
            "Открой Wallpaper Hub": "serpantinum settings wallpaper_search",
            "Где находятся настройки виджетов?": "serpantinum settings display display_widgets",
            "Как изменить рабочее пространство?": "Super+Left/Right",
            "How can I check RAM usage?": "Super+Shift+P",
        }
        with patch.object(CONTEXT, "memory_snapshot") as sample:
            for question, expected in cases.items():
                with self.subTest(question=question):
                    context, facts = CONTEXT.shell_context([{"role": "user", "content": question}])
                    self.assertIn(expected, context)
                    self.assertEqual(facts, {})
            context, _ = CONTEXT.shell_context([
                {"role": "user", "content": "Покажи использование ОЗУ"},
                {"role": "assistant", "content": "Earlier RAM answer"},
                {"role": "user", "content": "Write a Python function for memory safety"},
            ])
            sample.assert_not_called()
            self.assertNotIn("Relevant shell references", context)

    def test_snapshot_zero_missing_invalid_and_nonzero(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "meminfo"
            self.assertIsNone(CONTEXT.memory_snapshot(path))
            for counters in (
                "MemTotal: 1048576 kB\n", "MemTotal: 0 kB\nMemAvailable: 0 kB\n",
                "MemTotal: 4 kB\nMemAvailable: 8 kB\n",
            ):
                path.write_text(counters, encoding="ascii")
                self.assertIsNone(CONTEXT.memory_snapshot(path))
            path.write_text("MemTotal: 1048576 kB\nMemAvailable: 1048576 kB\n", encoding="ascii")
            self.assertEqual(CONTEXT.memory_snapshot(path)["percent"], 0)
            path.write_text("MemTotal: 8388608 kB\nMemAvailable: 6291456 kB\n", encoding="ascii")
            sample = CONTEXT.memory_snapshot(path)
            self.assertEqual(sample, {"usedGiB": 2.0, "totalGiB": 8.0, "availableGiB": 6.0, "percent": 25})
            with patch.object(CONTEXT, "memory_snapshot", return_value=sample):
                context, facts = CONTEXT.shell_context([{"role": "user", "content": "Покажи использование ОЗУ"}])
                self.assertEqual(facts, {"memory": {"status": "available", **sample}})
                self.assertIn("25% used", context)


if __name__ == "__main__":
    unittest.main()
