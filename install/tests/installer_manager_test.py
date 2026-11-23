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
from unittest.mock import Mock, patch
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

    def test_system_updates_http_requires_same_origin_and_has_no_install_actions(self):
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
                    with self.assertRaises(HTTPError) as rejected:
                        urlopen(Request(endpoint, data, headers), timeout=3)
                    with rejected.exception as response:
                        self.assertEqual(response.code, 404)
                    with urlopen(Request(server.origin + "/updates/status", headers=headers), timeout=3) as response:
                        self.assertEqual(json.load(response)["pm"], "dnf")
                    with self.assertRaises(HTTPError) as rejected:
                        urlopen(Request(server.origin + "/updates/upgrade", b'{"approval":"fake"}',
                                        headers), timeout=3)
                    with rejected.exception as response:
                        self.assertEqual(response.code, 400)
                finally:
                    server.shutdown()
                    thread.join(timeout=3)

    def test_system_approval_is_separate_one_time_and_disallowed_on_live(self):
        updates = installer.SystemUpdates("pacman")
        with tempfile.TemporaryDirectory() as work, patch.object(installer, "Run") as run:
            updates.work = type("Work", (), {"name": work})()
            updates.plan = dict(live=True, snapshot=True, packages=[{"name": "example"}])
            updates.approval = "system-plan"
            with self.assertRaisesRegex(ValueError, "Live"):
                updates.start("upgrade", {"approval": "system-plan"})
            self.assertFalse(run.called)
            updates.plan["live"] = False
            with self.assertRaisesRegex(ValueError, "approve"):
                updates.start("upgrade", {"approval": "desktop-plan"})
            updates.start("upgrade", {"approval": "system-plan", "snapshot": True})
            self.assertTrue(run.call_args.kwargs["system"])
            self.assertIn("--snapshot", run.call_args.args[0])
            self.assertIsNone(updates.approval)

    def test_system_history_contains_the_plan_and_native_journal(self):
        updates = installer.SystemUpdates("dnf")
        path = installer.installer_state_dir() / "system-update.fixture.log"
        path.write_text("Mirror unavailable\n", encoding="utf-8")
        updates.operation = "upgrade"
        updates.plan = {"packages": [{"name": "expat"}]}
        updates.run = Mock(path=str(path), status="Failed", exit_code=1)
        updates.run.report.return_value = {"exit_code": 1}
        updates.update()
        self.assertEqual(updates.history()[0]["code"], 1)
        report = updates.report(path.name)
        self.assertEqual(report["plan"], updates.plan)
        self.assertEqual(report["journal"], "Mirror unavailable\n")
        with self.assertRaises(ValueError):
            updates.report("../fixture.log")


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

    def test_phase_two_native_worker_keeps_all_three_tty_streams(self):
        work = Path(self.temp.name)
        sudo = work / "sudo"
        sudo.write_text(
            "#!/usr/bin/env bash\n"
            "if ! [[ -t 0 && -t 1 && -t 2 ]]; then\n"
            "  read -r hidden_prompt\n"
            "  exit 42\n"
            "fi\n"
            "stty -echo; printf '[Serpantinum sudo] Password: ' >&2; read -r password; stty echo\n"
            "[[ $password == fixture-password ]] || exit 43\n"
            "printf '\\nContinue transaction? [y/N] ' >&2; read -r answer\n"
            "[[ $answer == y ]] || exit 44\n"
            "printf '\\n(1/1) installing quickshell\\n'\n"
        )
        sudo.chmod(0o700)
        with patch.dict(os.environ, {"PATH": f"{work}:{os.environ['PATH']}"}):
            worker = shlex.join([sys.executable, str(installer.HERE / "native_packages.py"), "dnf", "quickshell"])
            run = self.start("printf '@@phase\\t2\\t6\\tInstalling\\tPackages\\n'; " + worker)
        self.until(run, lambda: run.secret and "Password" in run.prompt)
        run.answer("fixture-password", True)
        self.until(run, lambda: "Continue transaction?" in run.prompt)
        run.answer("y", False)
        self.until(run, lambda: run.exit_code is not None)
        self.assertEqual(run.exit_code, 0)
        self.assertNotIn("fixture-password", Path(run.path).read_text())

    def test_dnf_progress_with_unknown_eta_is_not_a_prompt(self):
        run = self.start("printf '[1/4] Total 0%% | 1.0 B/s | 4.0 KiB | ?'; sleep 30")
        self.until(run, lambda: "B/s" in run.pending)
        self.assertFalse(run.prompt)

    def test_native_network_failure_preserves_status_and_reason(self):
        work = Path(self.temp.name)
        sudo = work / "sudo"
        sudo.write_text("#!/usr/bin/env bash\nprintf 'Error: failed to download kitty: HTTP 404\\n' >&2\nexit 17\n")
        sudo.chmod(0o700)
        with patch.dict(os.environ, {"PATH": f"{work}:{os.environ['PATH']}"}):
            run = self.start(shlex.join([sys.executable, str(installer.HERE / "native_packages.py"), "dnf", "kitty"]))
        self.until(run, lambda: run.exit_code is not None)
        self.assertEqual(run.exit_code, 17)
        self.assertEqual(run.reports[-1]["download"], "FAILED")
        self.assertIn("HTTP 404", Path(run.path).read_text())

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
