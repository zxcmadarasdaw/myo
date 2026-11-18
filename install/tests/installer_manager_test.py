#!/usr/bin/env python3
"""Unit and protocol tests for the installer. No host packages are modified."""

import collections
import json
import os
from pathlib import Path
import shlex
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import manager as installer


def inventory():
    info = collections.defaultdict(list)
    info["meta"].append(["Fedora Linux", "fedora", "dnf", "2.5.1", "fixture", "fresh"])
    info["selected"].append(["hyprland"])
    info["component"].append(["Quickshell", "Missing", "Not available"])
    return info


class ManagerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        state = Path(temporary.name)
        patcher = patch.object(installer, "installer_state_dir", return_value=state)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_saved_plan_keeps_mode_and_rechecks_boot_and_cache(self):
        with patch.object(installer, "probe", side_effect=lambda *args: inventory()), patch.object(installer, "Run") as run:
            run.return_value.phase = 1
            run.return_value.completed = 0
            run.return_value.path = "fixture.log"
            run.return_value.exit_code = None
            manager = installer.Manager()
            plan = {"action": "install", "compositors": ["hyprland"], "options": [], "download_mode": "fast"}
            manager.start(approval=manager.review(plan)["approval"])
            manager.run.completed = 2
            manager.persist()
            reopened = installer.Manager()
            self.assertEqual(reopened.saved()["phase"], 3)
            self.assertEqual(reopened.saved()["plan"]["download_mode"], "fast")
            approved = reopened.review({}, saved=True)["approval"]
            reopened.start(approval=approved)
            run.assert_called_with(installer.backend_args("--manager-run", plan, 3))
            reopened.boot = "a-different-boot"
            self.assertEqual(reopened.saved()["phase"], 1)

    def test_plan_requires_approval_and_retries_the_same_step(self):
        with patch.object(installer, "probe", side_effect=lambda *args: inventory()), patch.object(installer, "Run") as run:
            run.return_value.phase = 1
            run.return_value.completed = 0
            run.return_value.path = "fixture.log"
            manager = installer.Manager()
            plan = {"action": "repair", "compositors": ["hyprland"], "options": ["backup"]}
            approval = manager.review(plan)["approval"]
            with self.assertRaisesRegex(ValueError, "Approve|approve"):
                manager.start(approval="different")
            manager.start(approval=approval)
            run.assert_called_once_with(installer.backend_args("--manager-run", plan))
            manager.run.exit_code = 1
            manager.run.phase = 3
            manager.review(dict(plan, options=[]))
            manager.start("retry")
            run.assert_called_with(installer.backend_args("--manager-run", plan, resume=3))

    def test_verify_cannot_enable_mutating_options(self):
        plan = installer.normalize_plan({"action": "verify", "compositors": ["hyprland"], "options": ["launch"]})
        self.assertEqual(plan["options"], [])

    def test_http_requires_same_origin_and_session_and_serves_the_user_interface(self):
        with patch.object(installer, "probe", side_effect=lambda *args: inventory()):
            with installer.LocalServer(("127.0.0.1", 0), installer.Handler) as server:
                server.host = f"127.0.0.1:{server.server_port}"
                server.origin = f"http://{server.host}"
                server.key = "fixture"
                server.manager = installer.Manager()
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()
                try:
                    with urlopen(server.origin, timeout=3) as response:
                        self.assertIn(b"Installation manager", response.read())
                        self.assertIn("frame-ancestors 'none'", response.headers["Content-Security-Policy"])
                    with self.assertRaises(HTTPError) as rejected:
                        urlopen(server.origin + "/inventory", timeout=3)
                    with rejected.exception as response:
                        self.assertEqual(response.code, 403)
                    endpoint = server.origin + "/review"
                    data = json.dumps({"action": "verify", "compositors": ["hyprland"], "options": []}).encode()
                    headers = {"X-Installer-Key": "fixture", "Origin": "http://example.invalid"}
                    with self.assertRaises(HTTPError) as rejected:
                        urlopen(Request(endpoint, data, headers), timeout=3)
                    with rejected.exception as response:
                        self.assertEqual(response.code, 403)
                    headers["Origin"] = server.origin
                    with urlopen(Request(endpoint, data, headers), timeout=3) as response:
                        self.assertTrue(json.load(response)["approval"])
                finally:
                    server.shutdown()
                    thread.join(timeout=3)


@unittest.skipUnless(sys.platform.startswith("linux"), "requires a Linux PTY")
class PtyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        state = patch.dict(os.environ, {"XDG_STATE_HOME": self.temp.name, "HOME": self.temp.name})
        state.start()
        self.addCleanup(state.stop)

    def start(self, script):
        run = installer.Run(["bash", "-c", script])
        self.addCleanup(self.stop, run)
        return run

    def stop(self, run):
        if run.fd is not None:
            run.cancel()
            self.until(run, lambda: run.exit_code is not None)

    def until(self, run, condition):
        end = time.monotonic() + 5
        while time.monotonic() < end:
            run.update()
            if condition():
                return
            time.sleep(0.02)
        self.fail(run.state(0))

    def test_native_prompt_secret_and_progress(self):
        secret = "no-log-fixture"
        run = self.start(
            "printf '@@phase\\t2\\t6\\tInstalling\\tPackages\\n'; "
            "printf 'Proceed? [y/N] '; read -r confirm; [ \"$confirm\" = y ] || exit 2; "
            "stty -echo; printf 'Password: '; read -r password; stty echo; "
            f"[ \"$password\" = {shlex.quote(secret)} ] || exit 3; "
            "printf '\\n(1/4) installing kitty\\n@@done\\t2\\n'"
        )
        self.until(run, lambda: "Proceed?" in run.prompt)
        self.assertIsNone(run.exit_code)
        run.answer("y", False)
        self.until(run, lambda: run.secret and "Password" in run.prompt)
        run.answer(secret, True)
        self.until(run, lambda: run.exit_code is not None)
        self.assertEqual(run.exit_code, 0)
        self.assertEqual(run.completed, 2)
        self.assertNotIn(secret, Path(run.path).read_text())
        self.assertIn("1 / 4", run.metrics["count"])

    def test_unknown_prompt_failure_and_cancellation(self):
        run = self.start("printf 'Select provider '; read -r provider; printf '\\nCould not resolve mirror\\n'; exit 4")
        self.until(run, lambda: "Select provider" in run.pending)
        self.assertFalse(run.prompt)
        run.answer("2", False)
        self.until(run, lambda: run.exit_code is not None)
        self.assertEqual(run.exit_code, 4)
        self.assertEqual(run.network, "Transfer error reported")

        build = self.start("trap 'exit 130' INT; printf '@@activity\\tBuilding\\tFixture\\n'; sleep 30")
        self.until(build, lambda: build.status == "Building")
        build.cancel()
        self.until(build, lambda: build.exit_code is not None)
        self.assertEqual(build.status, "Cancelled")


if __name__ == "__main__":
    unittest.main()
