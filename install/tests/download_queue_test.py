"""Offline queue contracts and real local-HTTP transfers; no host packages changed."""
import collections
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import download_queue as dq
import manager

DATA = b"fixture-package" * 2048


def package(name="quickshell", urls=None):
    return dq.Package(name, "1.2-1", "extra", len(DATA), name + ".pkg.tar.zst",
                      hashlib.sha256(DATA).hexdigest(), urls or ["https://mirror-a/" + name, "https://mirror-b/" + name])


class QueueTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.events = []
        self.calls = []

    def transfer(self, pkg, url, path, settings, notify):
        self.calls.append((pkg.name, url))
        path.write_bytes(DATA)
        dq.measured(pkg, len(DATA), 2, 1, len(DATA) // 2)
        notify(pkg)

    def queue(self, packages, transfer=None, **settings):
        return dq.Queue(packages, self.temp.name, dq.Settings(backoff=0, **settings),
                        self.events.append, transfer or self.transfer)

    def test_ten_packages_are_sequential_and_preserve_identity(self):
        packages = [package("pkg" + str(i)) for i in range(10)]
        active = []
        def transfer(*args):
            self.assertEqual(active, [])
            active.append(args[0].name)
            self.transfer(*args)
            active.pop()
        q = self.queue(packages, transfer, mode="stable")
        self.assertTrue(q.run())
        self.assertEqual([p.name for p in packages], [name for name, _ in self.calls])
        self.assertEqual({p.state for p in packages}, {"VERIFIED"})
        self.assertEqual(self.events[-1]["total"], 10)
        downloading = [e["package"] for e in self.events if (e.get("package") or {}).get("state") == "DOWNLOADING"]
        self.assertEqual(downloading[0]["name"], "pkg0")
        self.assertEqual(downloading[0]["version"], "1.2-1")

    def test_fixed_modes_schedule_real_concurrent_workers(self):
        for mode, count in (("stable", 1), ("balanced", 4), ("fast", 8)):
            with self.subTest(mode=mode):
                barrier = threading.Barrier(count, timeout=5)
                pkgs = [package(f"{mode}-{i}") for i in range(count * 2)]

                def transfer(*args):
                    barrier.wait()
                    self.transfer(*args)

                self.events.clear()
                self.assertTrue(self.queue(pkgs, transfer, mode=mode).run())
                self.assertEqual(max(e.get("active", 0) for e in self.events), count)

    def test_adaptive_increases_gradually_and_recovers_from_slowdown(self):
        controller = dq.Parallelism("adaptive")
        self.assertEqual(controller.limit, 4)
        for limit in range(4, 8):
            for _ in range(3):
                controller.sample(100, limit, True)
            self.assertEqual(controller.limit, limit + 1)
        controller.sample(100, 8, True)
        for _ in range(3):
            controller.sample(20, 8, True)
        self.assertEqual(controller.limit, 4)
        controller.reduce()
        controller.reduce()
        self.assertEqual(controller.limit, 1)
        for _ in range(3):
            controller.sample(100, 1, True)
        self.assertEqual(controller.limit, 2)

    def test_651_archives_and_partial_files_recover_after_interruption(self):
        pkgs = [package(f"queue-{i}") for i in range(651)]
        cache = Path(self.temp.name)
        for pkg in pkgs[:-2]:
            (cache / pkg.filename).write_bytes(DATA)
        (cache / (pkgs[-2].filename + ".part")).write_bytes(DATA[:1024])
        (cache / pkgs[-1].filename).write_bytes(b"corrupt")
        q = self.queue(pkgs, mode="fast")
        self.assertTrue(q.run())
        self.assertEqual(set(name for name, _ in self.calls), {p.name for p in pkgs[-2:]})
        self.assertEqual(q.report()["downloaded"], 651)
        q.transfer = Mock(side_effect=AssertionError("cache should be reused"))
        self.assertTrue(q.run())
        q.transfer.assert_not_called()

    def test_permission_error_is_per_file_and_keeps_other_archives(self):
        def transfer(pkg, *args):
            if pkg.name == "denied":
                raise PermissionError("Permission denied")
            self.transfer(pkg, *args)
        q = self.queue([package("denied"), package("good")], transfer)
        self.assertFalse(q.run())
        self.assertEqual(q.packages[0].attempts, 1)
        self.assertEqual(q.packages[0].error, "Permission denied")
        self.assertEqual(q.packages[1].state, "VERIFIED")

    def test_percentage_current_average_and_eta_use_received_bytes(self):
        p = package()
        p.size = 1000
        dq.measured(p, 400, 4, 2, 100)
        self.assertEqual((p.percent, p.rate, p.average, p.eta), (40, 50, 100, 12))
        dq.measured(p, 400, 5, 1, 0)
        self.assertEqual(p.rate, 0)
        self.assertIsNone(p.eta)

    def test_unknown_size_is_indeterminate(self):
        p = package()
        p.size = None
        dq.measured(p, 100, 2, 1, 100)
        self.assertIsNone(p.percent)
        self.assertIsNone(p.eta)

    def test_three_attempts_rotate_mirror_and_continue_after_failed_dependency(self):
        def transfer(pkg, *args):
            if pkg.name == "broken":
                self.calls.append((pkg.name, args[0]))
                raise dq.TransferError("HTTP 404")
            self.transfer(pkg, *args)
        q = self.queue([package("first"), package("broken"), package("last")], transfer)
        self.assertFalse(q.run())
        self.assertEqual(q.packages[1].attempts, 3)
        self.assertEqual(q.packages[1].error, "HTTP 404")
        self.assertEqual(q.packages[2].state, "VERIFIED")
        self.assertEqual([url for name, url in self.calls if name == "broken"],
                         ["https://mirror-a/broken", "https://mirror-b/broken", "https://mirror-a/broken"])
        self.assertIn("DEFERRED", [e["package"]["state"] for e in self.events if e.get("package")])

    def test_retry_checks_cache_and_only_fetches_failed(self):
        p, broken = package("good"), package("broken")
        def fail(pkg, *args):
            if pkg.name == "broken":
                raise dq.TransferError("DNS resolution failure")
            self.transfer(pkg, *args)
        q = self.queue([p, broken], fail)
        self.assertFalse(q.run())
        self.calls.clear()
        q.transfer = self.transfer
        self.assertTrue(q.run())
        self.assertEqual([n for n, _ in self.calls], ["broken"])
        self.assertEqual(broken.error, "")

    def test_corrupt_cache_is_redownloaded(self):
        p = package()
        (Path(self.temp.name) / p.filename).write_bytes(b"bad")
        self.assertTrue(self.queue([p]).run())
        self.assertEqual(len(self.calls), 1)

    def test_checksum_mismatch_blocks_package(self):
        def corrupt(pkg, url, path, *args):
            path.write_bytes(b"x" * len(DATA))
        p = package()
        self.assertFalse(self.queue([p], corrupt).run())
        self.assertEqual(p.error, "Checksum mismatch")
        self.assertFalse((Path(self.temp.name) / p.filename).exists())

    def test_low_space_fails_once_and_reports_actual_reason(self):
        p = package()
        with patch.object(dq.shutil, "disk_usage", return_value=Mock(free=1)):
            q = self.queue([p])
            self.assertFalse(q.run())
        self.assertEqual(p.attempts, 1)
        self.assertEqual(p.error, "Insufficient disk space")
        self.assertEqual(self.calls, [])
        self.assertIn("Insufficient", q.storage["warning"])

    def test_missing_dependency_blocks_entire_install_but_keeps_successes(self):
        def transfer(pkg, *args):
            if pkg.name == "required-lib":
                raise dq.TransferError("Connection reset")
            self.transfer(pkg, *args)
        q = self.queue([package("app"), package("required-lib")], transfer)
        backend = Mock()
        self.assertEqual(dq.run_transaction(backend, q, ["app"]), 1)
        backend.verify.assert_not_called()
        backend.install.assert_not_called()
        self.assertTrue((q.cache / q.packages[0].filename).exists())

    def test_signature_error_blocks_native_install(self):
        q = self.queue([package()])
        backend = Mock()
        backend.resolve.return_value = q.packages
        backend.verify.side_effect = dq.TransferError("Invalid package signature: quickshell")
        self.assertEqual(dq.run_transaction(backend, q, ["quickshell"]), 1)
        backend.install.assert_not_called()
        self.assertEqual(q.packages[0].error, "Invalid package signature")
        self.assertEqual(q.stage, "BLOCKED")
        self.assertEqual(q.report()["download"], "SUCCESS")
        self.assertEqual(q.report()["verification"], "FAILED")
        self.assertEqual(q.report()["installation"], "PENDING")

    def test_install_failure_keeps_checksum_and_verification_success(self):
        q = self.queue([package()])
        backend = Mock()
        backend.resolve.return_value = q.packages
        backend.install.side_effect = dq.TransferError("could not satisfy dependencies")
        self.assertEqual(dq.run_transaction(backend, q, ["quickshell"]), 1)
        self.assertEqual(q.report()["downloaded"], 1)
        self.assertEqual(q.report()["verification"], "SUCCESS")
        self.assertEqual(q.report()["installation"], "FAILED")
        self.assertIn("could not satisfy dependencies", q.error)

    def test_metadata_drift_blocks_commit(self):
        q = self.queue([package()])
        backend = Mock()
        other = package()
        other.version = "changed"
        backend.resolve.return_value = [other]
        self.assertEqual(dq.run_transaction(backend, q, ["app"]), 1)
        backend.install.assert_not_called()

    def test_native_hook_error_is_reported_when_install_exits_zero(self):
        q = self.queue([package()])
        backend = Mock()
        backend.resolve.return_value = q.packages
        process = Mock()
        process.stderr.read1.side_effect = [
            b"err", b"or: post-transaction hook failed\n", b"another line\n", b"",
        ]
        process.wait.return_value = 0
        backend.install.side_effect = lambda queue, targets: dq.install_command(["pacman"], queue)
        with patch.object(dq.subprocess, "Popen") as popen, patch.object(dq.sys, "stderr") as stderr:
            popen.return_value.__enter__.return_value = process
            self.assertEqual(dq.run_transaction(backend, q, ["quickshell"]), 0)
        self.assertEqual(q.report()["installation"], "SUCCESS_WITH_WARNINGS")
        self.assertEqual(q.report()["native_errors"], ["error: post-transaction hook failed"])
        self.assertEqual(q.packages[0].state, "INSTALLED")
        self.assertEqual(stderr.buffer.write.call_count, 3)

    def test_cache_server_error_does_not_treat_openssl_as_a_tls_failure(self):
        self.assertEqual(dq.reason("Could not open file /cache/openssl-4.1.0.pkg.tar.zst", 37),
                         "Mirror file unavailable")

    def test_native_install_runs_once_after_verification(self):
        q = self.queue([package("app"), package("lib")])
        backend = Mock()
        backend.resolve.return_value = q.packages
        backend.install.return_value = 0
        self.assertEqual(dq.run_transaction(backend, q, ["app"]), 0)
        backend.verify.assert_called_once_with(q, ["app"])
        backend.install.assert_called_once_with(q, ["app"])
        self.assertEqual({p.state for p in q.packages}, {"INSTALLED"})

    def test_cancel_cleans_partial_and_stops_queue(self):
        def cancelled(pkg, url, path, *args):
            path.write_bytes(b"part")
            raise KeyboardInterrupt
        q = self.queue([package(), package("second")], cancelled, mode="stable")
        with self.assertRaises(KeyboardInterrupt):
            q.run()
        self.assertEqual(q.stage, "CANCELLED")
        self.assertEqual(q.packages[0].error, "Cancelled by user")
        self.assertFalse(list(q.cache.rglob("*.part")))

    def test_reports_are_structured_and_do_not_include_repository_secrets(self):
        p = package(urls=["https://user:password@mirror/path-secret?token=secret"])
        self.assertTrue((q := self.queue([p])).run())
        report = json.dumps(q.report())
        self.assertNotIn("password", report)
        self.assertNotIn("path-secret", report)
        self.assertNotIn("token=", report)
        self.assertIn('"downloaded": 1', report)
        self.assertEqual(dq.redact("Error https://u:p@host/private?secret=1"), "Error host/[redacted]")

    def test_error_taxonomy(self):
        for msg, expected in [("could not resolve host", "DNS resolution failure"), ("HTTP 403", "HTTP 403"),
                              ("SSL certificate", "SSL/TLS error"), ("target not found", "Package not found"),
                              ("permission denied", "Permission denied"), ("conflicting dependencies", "Dependency conflict"),
                              ("failed to connect", "Mirror unavailable"), ("mystery", "Unknown error")]:
            with self.subTest(msg=msg):
                self.assertEqual(dq.reason(msg), expected)

    def test_settings_require_finite_positive_intervals(self):
        for kwargs in ({"warning": 60, "timeout": 30}, {"attempts": 0}, {"connect": 0}, {"timeout": float("inf")}):
            with self.assertRaises(ValueError):
                dq.Settings(**kwargs)


class NativeAdapterTests(unittest.TestCase):
    def test_full_arch_upgrade_keeps_one_complete_transaction(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(dq, "command") as command, \
             patch.object(dq.tempfile, "mkdtemp", side_effect=lambda **kwargs: str(Path(temp) / "native")), \
             patch.object(dq.Path, "chmod"), patch.object(dq.Path, "rmdir"):
            command.side_effect = lambda args: "[options]\n[core]\nServer = https://mirror\n" if args == ["pacman-conf"] else ""
            backend = dq.Pacman(temp, temp, upgrade=True)
            backend.resolve(["app"])
            self.assertIn("-Spu", command.call_args.args[0])
            backend.verify(Mock(packages=[]), ["app"])
            self.assertIn("-Suw", command.call_args.args[0])
            with patch.object(dq, "install_command", return_value=0) as install:
                backend.install(Mock(), ["app"])
            self.assertIn("-Su", install.call_args.args[0])
            self.assertNotIn("-Sy", install.call_args.args[0])

    def test_cachyos_repositories_signatures_and_parallel_policy_preserved(self):
        config = "[options]\nParallelDownloads = 5\nSigLevel = Required DatabaseOptional\n[core]\nServer = https://core\n[cachyos-v3]\nSigLevel = Required\nServer = https://cachy\nCacheServer = https://configured-cache\n"
        with tempfile.TemporaryDirectory() as temp, patch.object(dq, "command") as command:
            def output(args):
                if args == ["pacman-conf"]:
                    return config
                if args == ["pacman-conf", "CacheDir"]:
                    return temp
                if "--print-format" in args:
                    return "SPQ:quickshell\t1.2\tcachyos-v3\t100\tquickshell.pkg.tar.zst\t" + "a" * 64 + "\thttps://cachy/quickshell.pkg.tar.zst\tQUJD\n"
                if args[-1] == "CacheServer":
                    return "https://configured-cache\n"
                return "https://cachy\nhttps://second\n"
            command.side_effect = output
            backend = dq.Pacman(temp, temp)
            self.assertIn("ParallelDownloads = 4", backend.config.read_text())
            self.assertIn("Server = file:///dev/null", backend.offline.read_text())
            self.assertNotIn("https://", backend.offline.read_text())
            self.assertNotIn("XferCommand", backend.offline.read_text())
            self.assertNotIn("ParallelDownloads = 5", backend.config.read_text())
            self.assertIn("SigLevel = Required", backend.config.read_text())
            self.assertIn("[cachyos-v3]", backend.config.read_text())
            packages = backend.resolve(["quickshell"])
            self.assertEqual(packages[0].repository, "cachyos-v3")
            self.assertEqual(packages[0].urls, [
                "https://configured-cache/quickshell.pkg.tar.zst",
                "https://cachy/quickshell.pkg.tar.zst",
                "https://second/quickshell.pkg.tar.zst",
            ])
            q = dq.Queue(packages, temp, emit=lambda e: None)
            with patch.object(dq.Path, "symlink_to") as link, patch.object(backend, "native"):
                backend.verify(q, ["quickshell"])
            self.assertEqual((q.cache / "quickshell.pkg.tar.zst.sig").read_bytes(), b"ABC")
            self.assertEqual(link.call_args_list[0].args, (q.cache / "quickshell.pkg.tar.zst",))
            self.assertEqual(link.call_args_list[1].args, (q.cache / "quickshell.pkg.tar.zst.sig",))
            with patch.object(dq.tempfile, "mkdtemp", return_value=temp), patch.object(dq.Path, "rmdir"):
                backend.native(q, ["quickshell"], download_only=True)
            args = command.call_args.args[0]
            self.assertIn("-Sw", args)
            self.assertNotIn("--nodeps", args)
            with patch.object(dq, "install_command", return_value=0) as install, \
                 patch.object(dq.tempfile, "mkdtemp", return_value=temp), patch.object(dq.Path, "rmdir"):
                backend.install(q, ["quickshell"])
            self.assertIn("-S", install.call_args.args[0])

    def test_manager_consumes_structured_progress_and_exports(self):
        run = manager.Run.__new__(manager.Run)
        run.downloads, run.queue, run.reports = {}, {}, []
        run.metrics = {}
        run.append = Mock()
        p = package()
        p.state = "DOWNLOADING"
        dq.measured(p, 10, 1, 1, 10)
        run.consume("@@queue\t" + json.dumps({"stage": "DOWNLOAD", "package": p.public(), "total": 1}))
        self.assertEqual(run.downloads[p.name]["received"], 10)
        self.assertEqual(run.metrics["percent"], 10 * 100 / len(DATA))
        run.consume('@@report\t{"total":1,"downloaded":0,"failed":1,"stage":"BLOCKED"}')
        self.assertEqual(len(run.reports[0]["packages"]), 1)
        text = manager.report_text({"status": "Failed", "transactions": run.reports, "current": {}})
        self.assertIn("quickshell", text)
        self.assertIn("BLOCKED", text)


@unittest.skipUnless(shutil.which("curl"), "requires curl for actual HTTP transfers")
class LocalHttpTests(unittest.TestCase):
    def setUp(self):
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def do_HEAD(self):
                self.send_response(200)
                self.end_headers()
            def do_GET(self):
                self.send_response(404 if self.path == "/404" else 200)
                self.end_headers()
                if self.path == "/stall":
                    time.sleep(1.5)
                    return
                for chunk in [DATA[:1024], DATA[1024:]]:
                    try:
                        self.wfile.write(chunk)
                        self.wfile.flush()
                    except OSError:
                        return
                    time.sleep(0.35)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.url = "http://127.0.0.1:" + str(self.server.server_port)

    def test_actual_http_bytes_zero_interval_does_not_fail(self):
        p = package(urls=[self.url + "/ok"])
        events = []
        q = dq.Queue([p], self.temp.name, dq.Settings(warning=1, timeout=2, backoff=0), events.append)
        self.assertTrue(q.run())
        self.assertEqual(p.received, len(DATA))
        snapshots = [e["package"] for e in events if e.get("package")]
        self.assertTrue(any(x["received"] == 1024 for x in snapshots))
        self.assertTrue(any(x["rate"] == 0 for x in snapshots))
        self.assertEqual(p.percent, 100)

    def test_stall_warns_then_times_out_with_bounded_retry(self):
        p = package(urls=[self.url + "/stall"])
        events = []
        q = dq.Queue([p], self.temp.name, dq.Settings(warning=.2, timeout=.5, attempts=1, backoff=0), events.append)
        start = time.monotonic()
        self.assertFalse(q.run())
        self.assertLess(time.monotonic() - start, 4)
        self.assertEqual(p.error, "Connection timeout")
        self.assertTrue(any(e.get("package", {}).get("warning") for e in events if e.get("package")))
        self.assertIn("no byte progress", p.detail)

    def test_stalled_transfer_reduces_adaptive_slots_without_stopping_other_downloads(self):
        pkgs = [package("stalled", [self.url + "/stall", self.url + "/ok"])]
        pkgs += [package(f"healthy-{i}", [self.url + "/ok"]) for i in range(8)]
        events = []
        q = dq.Queue(pkgs, self.temp.name, dq.Settings(mode="adaptive", warning=.2, timeout=.5, backoff=0), events.append)
        self.assertTrue(q.run())
        self.assertEqual(pkgs[0].attempts, 2)
        self.assertEqual(pkgs[0].history[0]["reason"], "Connection timeout")
        self.assertTrue(all(p.attempts == 1 for p in pkgs[1:]))
        self.assertEqual(max(e.get("active", 0) for e in events), 4)
        self.assertTrue(any(e.get("limit") == 2 for e in events))

    def test_http404_fallback_to_next_mirror(self):
        p = package(urls=[self.url + "/404", self.url + "/ok"])
        self.assertTrue(dq.Queue([p], self.temp.name, dq.Settings(backoff=0), lambda e: None).run())
        self.assertEqual(p.attempts, 2)
        self.assertEqual(p.history[0]["reason"], "HTTP 404")


if __name__ == "__main__":
    unittest.main()
