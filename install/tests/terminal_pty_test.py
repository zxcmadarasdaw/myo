"""Desktop Terminal widget: PTY bridge (src/scripts/system/serp_pty.py).

    python3 install/tests/terminal_pty_test.py

On Linux this starts real pseudo-terminals:
  * an interactive bash: input goes in, coloured output comes back, `stty
    size` follows resize messages, closing stdin hangs the shell up;
  * --cmd / exit codes, --require for a missing program, --repeat (monitor);
  * UTF-8 split across reads is decoded intact.
On systems without pty/termios (Windows) it only checks that the bridge
reports a clean error instead of crashing.
"""
import json
import os
import subprocess
import sys
import time
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BRIDGE = os.path.join(ROOT, "src", "scripts", "system", "serp_pty.py")
POSIX = os.name == "posix"


class Bridge:
    def __init__(self, *args):
        self.p = subprocess.Popen([sys.executable, BRIDGE] + list(args),
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True, bufsize=1)
        self.msgs = []
        self.out = ""

    def send(self, obj):
        self.p.stdin.write(json.dumps(obj) + "\n")
        self.p.stdin.flush()

    def read_until(self, pred, timeout=10.0):
        import select
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if pred():
                return True
            r, _, _ = select.select([self.p.stdout], [], [], 0.1)
            if r:
                line = self.p.stdout.readline()
                if not line:
                    return pred()
                msg = json.loads(line)
                self.msgs.append(msg)
                if msg.get("t") == "out":
                    self.out += msg["d"]
        return pred()

    def types(self):
        return [m["t"] for m in self.msgs]

    def close(self):
        try:
            self.p.stdin.close()
        except OSError:
            pass
        try:
            self.p.wait(timeout=5)
        finally:
            if self.p.poll() is None:
                self.p.kill()
        self.p.stdout.close()
        self.p.stderr.close()


@unittest.skipUnless(POSIX, "needs Linux pseudo-terminals")
class PtyBridgeTest(unittest.TestCase):
    def test_interactive_shell_io_and_resize(self):
        b = Bridge("--shell", "bash", "--cols", "100", "--rows", "30")
        try:
            self.assertTrue(b.read_until(lambda: "started" in b.types()))
            b.send({"t": "in", "d": "export PS1='$ '; printf '\\033[31mRED\\033[0m %s\\n' ok\r"})
            self.assertTrue(b.read_until(lambda: "\x1b[31mRED\x1b[0m ok" in b.out), b.out[-400:])
            b.send({"t": "in", "d": "stty size\r"})
            self.assertTrue(b.read_until(lambda: "30 100" in b.out), b.out[-400:])
            b.send({"t": "resize", "c": 72, "r": 20})
            b.send({"t": "in", "d": "stty size\r"})
            self.assertTrue(b.read_until(lambda: "20 72" in b.out), b.out[-400:])
            b.send({"t": "in", "d": "echo $TERM $SERPANTINUM_TERMINAL\r"})
            self.assertTrue(b.read_until(lambda: "xterm-256color 1" in b.out), b.out[-400:])
        finally:
            b.close()
        self.assertEqual(b.p.returncode, 0)              # stdin closed: shell hung up, bridge exits

    def test_command_exit_code(self):
        b = Bridge("--cmd", "echo hi; exit 3")
        try:
            self.assertTrue(b.read_until(lambda: "exit" in b.types()))
            self.assertIn("hi", b.out)
            self.assertEqual([m for m in b.msgs if m["t"] == "exit"][0]["code"], 3)
        finally:
            b.close()

    def test_missing_program(self):
        b = Bridge("--require", "serpantinum-no-such-program-xyz", "--cmd", "serpantinum-no-such-program-xyz")
        try:
            self.assertTrue(b.read_until(lambda: "missing" in b.types()))
            self.assertEqual(b.msgs[0], {"t": "missing", "prog": "serpantinum-no-such-program-xyz"})
            self.assertNotIn("started", b.types())       # nothing was run
        finally:
            b.close()

    def test_monitor_repeats_and_clears(self):
        b = Bridge("--cmd", "echo tick", "--repeat", "0.5")
        try:
            self.assertTrue(b.read_until(lambda: b.out.count("tick") >= 2, timeout=8))
            self.assertGreaterEqual(b.out.count("\x1b[H\x1b[2J"), 2)
            self.assertNotIn("exit", b.types())
        finally:
            b.close()

    def test_utf8_survives_chunking(self):
        text = "Привет, мир — 中文 😀"
        b = Bridge("--cmd", "printf '%s' '" + text + "'")
        try:
            self.assertTrue(b.read_until(lambda: "exit" in b.types()))
            self.assertIn(text, b.out)
            self.assertNotIn("�", b.out)
        finally:
            b.close()


@unittest.skipIf(POSIX, "only for systems without pseudo-terminals")
class NoPtyTest(unittest.TestCase):
    def test_reports_error(self):
        out = subprocess.run([sys.executable, BRIDGE], capture_output=True, text=True, timeout=20)
        msg = json.loads(out.stdout.strip().splitlines()[0])
        self.assertEqual(msg["t"], "error")
        self.assertEqual(out.returncode, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
