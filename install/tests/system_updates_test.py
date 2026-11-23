#!/usr/bin/env python3
"""Tests for system update planning. All command and package fixtures are isolated."""

import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import system_updates as updates
from download_queue import Package, TransferError, reason


class UpdateTests(unittest.TestCase):
    def test_dnf5_transaction_reads_download_and_net_disk_change(self):
        transaction = """Package  Arch    Version  Repository  Size
Upgrading:
 kernel-core x86_64 7.0-2 updates 71.2 MiB
 example noarch 2-1 updates 2.0 KiB

Transaction Summary:
 Upgrading: 2 packages
Total size of inbound packages is 72 MiB. Need to download 63 MiB.
After this operation, 12 KiB extra will be used (install 148 MiB, remove 148 MiB).
Operation aborted by the user.
"""
        preview = subprocess.CompletedProcess([], 1, stdout=transaction, stderr="")
        security = subprocess.CompletedProcess([], 100, stdout="", stderr="")
        with patch.object(updates, "capture", side_effect=[preview, security]) as capture:
            result = updates.check_dnf(Path("."), "fast")
        self.assertEqual([p["name"] for p in result["packages"]], ["kernel-core", "example"])
        self.assertEqual(result["download"], 63 * updates.MIB)
        self.assertEqual(result["change"], 12 * 1024)
        self.assertTrue(result["security"])
        self.assertIn("--assumeno", capture.call_args_list[0].args[0])

    def test_cannot_turn_a_failed_repo_into_an_up_to_date_result(self):
        result = subprocess.CompletedProcess([], 1, stdout="Nothing to do.", stderr="Failed to download repo")
        with patch.object(updates, "capture", return_value=result):
            with self.assertRaisesRegex(TransferError, "Failed to download"):
                updates.check_dnf(Path("."), "stable")

    def test_archive_in_system_cache_saves_network_but_needs_copy_space(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            system_cache = root / "system"
            private_cache = root / "private"
            system_cache.mkdir()
            private_cache.mkdir()
            data = b"example archive"
            pkg = Package("example", "2", "core", len(data), "example.pkg", hashlib.sha256(data).hexdigest())
            backend = SimpleNamespace(cache=private_cache, system_caches=[system_cache])
            self.assertEqual(updates.cache_requirements(backend, [pkg]), (len(data), len(data)))
            (system_cache / pkg.filename).write_bytes(data)
            self.assertEqual(updates.cache_requirements(backend, [pkg]), (len(data), 0))
            (private_cache / pkg.filename).write_bytes(data)
            self.assertEqual(updates.cache_requirements(backend, [pkg]), (0, 0))

    def test_system_package_manager_lock_is_never_unlinked(self):
        with tempfile.TemporaryDirectory() as folder:
            db = Path(folder)
            lock = db / "db.lck"
            lock.touch()
            with self.assertRaisesRegex(TransferError, "locked"):
                updates.lock_check(db)
            self.assertTrue(lock.is_file())

    def test_live_update_is_rejected_before_reading_or_running_the_plan(self):
        if not sys.platform.startswith("linux"):
            self.skipTest("requires Linux file locks")
        with patch.object(updates, "live_session", return_value=True):
            with self.assertRaisesRegex(TransferError, "Live"):
                updates.upgrade("pacman", Path("missing"), "stable", False)

    def test_snapshot_is_opt_in_and_requires_a_configured_root(self):
        with patch.object(updates, "snapshot_config", return_value=None) as config, \
                patch.object(updates.subprocess, "run") as run, patch.object(updates, "activity"):
            updates.make_snapshot(False)
            config.assert_not_called()
            with self.assertRaisesRegex(TransferError, "snapshot is unavailable"):
                updates.make_snapshot(True)
            run.assert_not_called()
            config.return_value = "system"
            updates.make_snapshot(True)
            args = run.call_args.args[0]
            self.assertEqual(args[:5], ["sudo", "snapper", "-c", "system", "create"])
            self.assertTrue(run.call_args.kwargs["check"])

    def test_void_dry_run_uses_in_memory_repositories_and_lists_updates(self):
        output = subprocess.CompletedProcess([], 0, stdout="xbps-0.59_1 update x86_64 repo 2MB 300KB\n", stderr="")
        with patch.object(updates, "capture", return_value=output) as capture:
            plan = updates.check_void()
        capture.assert_called_once_with(["xbps-install", "-Mun"])
        self.assertEqual(plan["packages"][0]["name"], "xbps-0.59_1")
        self.assertEqual(plan["download"], 300 * 1024)

    def test_native_network_failure_reasons(self):
        for message, expected in [
            ("SSL_ERROR_SYSCALL", "SSL/TLS error"),
            ("connection timeout", "Connection timeout"),
            ("HTTP 404", "HTTP 404"),
            ("error invoking external downloader", "External downloader failed"),
        ]:
            with self.subTest(message=message):
                self.assertEqual(reason(message), expected)


if __name__ == "__main__":
    unittest.main()
