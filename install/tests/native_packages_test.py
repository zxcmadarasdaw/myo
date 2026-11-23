"""Command, trust diagnostics and recovery contracts for desktop transactions."""

import argparse
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import native_packages as packages


class NativeTests(unittest.TestCase):
    def test_dnf_uses_native_cache_and_signatures_for_each_supported_cli(self):
        args = argparse.Namespace(backend="dnf", repo_option=["--disablerepo=terra"],
                                  refresh=True, operation="upgrade", targets=["kitty"])
        for version, key in [("/usr/bin/dnf5", "pkg_gpgcheck"), (None, "gpgcheck")]:
            with self.subTest(version=version), patch.object(packages.shutil, "which", return_value=version):
                command = packages.native_command(args, ".", 8)
                self.assertIn("--disablerepo=terra", command)
                self.assertIn(f"--setopt=*.{key}=True", command)
                self.assertIn("--setopt=localpkg_gpgcheck=True", command)
                self.assertIn("--setopt=keepcache=True", command)
                self.assertIn("--setopt=copr:copr.fedorainfracloud.org:sdegler:hyprland.excludepkgs=kitty,kitty-*", command)
                self.assertIn("--setopt=max_parallel_downloads=8", command)
                self.assertEqual(command[-4:], ["--refresh", "upgrade", "--", "kitty"])
                self.assertFalse({"--cacheonly", "--nogpgcheck", "-y"} & set(command))

    def test_pacman_has_one_transaction_with_native_cache_mirrors_and_signature_policy(self):
        config = "[options]\nSigLevel = Required DatabaseOptional\nXferCommand = /usr/bin/false\nDisableDownloadTimeout\n" \
                 "[core]\nServer = https://mirror/core\nCacheServer = https://cache/core\n"
        args = argparse.Namespace(backend="pacman", upgrade=True, targets=["hyprland", "quickshell"])
        with tempfile.TemporaryDirectory() as folder, patch.object(packages, "command", side_effect=[config, "/cache"]), \
                patch.object(packages, "cache_root", return_value=Path(folder)):
            (Path(folder) / "pacman").mkdir()
            command = packages.native_command(args, folder, 4)
            resolved = (Path(folder) / "pacman.conf").read_text()
        self.assertEqual(command[-5:], ["-Syu", "--needed", "--", "hyprland", "quickshell"])
        self.assertIn("/cache", command)
        self.assertNotIn("-Sy", command)
        for line in ("SigLevel = Required", "Server = https://mirror", "CacheServer = https://cache",
                     "ParallelDownloads = 4", "CheckSpace"):
            self.assertIn(line, resolved)
        self.assertNotIn("XferCommand", resolved)
        self.assertNotIn("DisableDownloadTimeout", resolved)

    def test_reports_trust_failure_separately_and_keeps_the_native_detail(self):
        message = "Error: kitty.rpm: Header OpenPGP signature: NOKEY"
        with patch.object(sys, "argv", ["native_packages", "dnf", "kitty"]), \
                patch.object(packages, "install_command", side_effect=packages.TransferError(message)), \
                patch.object(packages, "emit") as emit, patch("builtins.print"):
            self.assertEqual(packages.main(), 1)
        report = emit.call_args.args[1]
        self.assertEqual(report["verification"], "FAILED")
        self.assertEqual(report["error"], message)
        self.assertIsNone(report["downloaded"])

    def test_adaptive_profile_changes_only_between_native_transactions(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(packages, "cache_root", return_value=Path(folder)):
            parallel, preference = packages.profile("pacman", "adaptive")
            self.assertEqual(parallel, 4)
            packages.update_profile(preference, parallel, False, True)
            self.assertEqual(packages.profile("pacman", "adaptive")[0], 2)
            packages.update_profile(preference, 2, True, False)
            self.assertEqual(packages.profile("pacman", "adaptive")[0], 3)
            self.assertEqual(packages.profile("pacman", "fast")[0], 8)


if __name__ == "__main__":
    unittest.main()
