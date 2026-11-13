#!/usr/bin/env python3
"""PTY bridge for the Serpantinum desktop terminal widget.

    python3 serp_pty.py [--shell auto|bash|zsh] [--cmd COMMAND] [--require PROG]
                        [--repeat SECONDS] [--cols N] [--rows N] [--cwd DIR]

Runs a real shell (or one command) on a pseudo-terminal and relays it as
JSON lines, so the QML side can stay a pure terminal emulator/renderer.

stdin, one JSON object per line:
  {"t": "in", "d": "text"}            keystrokes / paste, written to the PTY
  {"t": "resize", "c": 80, "r": 24}   new size; the kernel sends SIGWINCH

stdout, one JSON object per line:
  {"t": "started", "pid": 1234, "argv": [...]}
  {"t": "out", "d": "decoded UTF-8 output"}
  {"t": "exit", "code": 0}
  {"t": "missing", "prog": "cava"}     --require PROG is not installed
  {"t": "error", "msg": "..."}

--cmd runs COMMAND with `sh -c`; without it an interactive shell starts.
--repeat N re-runs --cmd every N seconds, clearing the screen before each
run (the "command monitor" mode). Closing stdin hangs up the PTY and exits;
the shell side never runs anything the user did not configure.
"""
import codecs
import json
import os
import select
import shutil
import signal
import sys
import time

try:
    import fcntl
    import pty
    import struct
    import termios
except ImportError:      # not a POSIX system: the widget shows the error
    pty = None

FLUSH_SECONDS = 0.012    # coalesce bursts of output into one message
MAX_CHUNK = 65536


def emit(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def parse_args(argv):
    opts = {"shell": "auto", "cmd": None, "require": None, "repeat": 0.0,
            "cols": 80, "rows": 24, "cwd": None}
    i = 0
    while i < len(argv):
        key = argv[i]
        val = argv[i + 1] if i + 1 < len(argv) else None
        if key in ("--shell", "--cmd", "--require", "--cwd") and val is not None:
            opts[key[2:]] = val
            i += 2
        elif key in ("--cols", "--rows") and val is not None:
            try:
                opts[key[2:]] = max(2, min(1000, int(val)))
            except ValueError:
                pass
            i += 2
        elif key == "--repeat" and val is not None:
            try:
                opts["repeat"] = max(0.5, min(86400.0, float(val)))
            except ValueError:
                pass
            i += 2
        else:
            i += 1
    return opts


def pick_shell(choice):
    """bash or zsh; "auto" follows $SHELL when it is one of them."""
    wanted = []
    if choice in ("bash", "zsh"):
        wanted.append(choice)
    else:
        login = os.path.basename(os.environ.get("SHELL", ""))
        if login in ("bash", "zsh"):
            wanted.append(login)
    wanted += ["bash", "zsh", "sh"]
    for name in wanted:
        path = shutil.which(name)
        if path:
            return path
    return "/bin/sh"


def set_size(fd, cols, rows):
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    except OSError:
        pass


def spawn(argv, opts):
    pid, fd = pty.fork()
    if pid == 0:                              # child
        try:
            if opts["cwd"] and os.path.isdir(opts["cwd"]):
                os.chdir(opts["cwd"])
            elif os.environ.get("HOME"):
                os.chdir(os.environ["HOME"])
        except OSError:
            pass
        env = dict(os.environ)
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["SERPANTINUM_TERMINAL"] = "1"
        env.pop("QT_QPA_PLATFORM_THEME", None)
        try:
            os.execvpe(argv[0], argv, env)
        except OSError as e:
            os.write(2, ("serp_pty: cannot run %s: %s\r\n" % (argv[0], e)).encode())
        os._exit(127)
    set_size(fd, opts["cols"], opts["rows"])
    return pid, fd


def hang_up(pid, fd):
    try:
        os.close(fd)
    except OSError:
        pass
    for sig in (signal.SIGHUP, signal.SIGTERM):
        try:
            os.killpg(pid, sig)
        except (OSError, ProcessLookupError):
            pass
    deadline = time.monotonic() + 0.5
    while time.monotonic() < deadline:
        try:
            done, _ = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            return
        if done:
            return
        time.sleep(0.02)
    try:
        os.killpg(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    except (OSError, ChildProcessError):
        pass


def exit_code(status):
    if os.WIFEXITED(status):
        return os.WEXITSTATUS(status)
    if os.WIFSIGNALED(status):
        return 128 + os.WTERMSIG(status)
    return 1


class Bridge:
    def __init__(self, opts):
        self.opts = opts
        self.decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
        self.pending = ""
        self.pending_since = 0.0
        self.stdin_buf = b""
        self.stdin_open = True

    def flush(self):
        if self.pending:
            emit({"t": "out", "d": self.pending})
            self.pending = ""

    def queue(self, text):
        if not text:
            return
        if not self.pending:
            self.pending_since = time.monotonic()
        self.pending += text
        if len(self.pending) >= MAX_CHUNK:
            self.flush()

    def handle_line(self, line, fd):
        try:
            msg = json.loads(line)
        except ValueError:
            return
        if not isinstance(msg, dict):
            return
        if msg.get("t") == "in" and isinstance(msg.get("d"), str) and fd is not None:
            data = msg["d"].encode("utf-8", "replace")
            while data:
                try:
                    n = os.write(fd, data)
                except BlockingIOError:
                    select.select([], [fd], [], 0.05)
                    continue
                except OSError:
                    break
                data = data[n:]
        elif msg.get("t") == "resize":
            try:
                self.opts["cols"] = max(2, min(1000, int(msg.get("c"))))
                self.opts["rows"] = max(2, min(1000, int(msg.get("r"))))
            except (TypeError, ValueError):
                return
            if fd is not None:
                set_size(fd, self.opts["cols"], self.opts["rows"])

    def read_stdin(self, fd):
        """Returns False when stdin closed (the shell went away)."""
        try:
            chunk = os.read(sys.stdin.fileno(), 65536)
        except OSError:
            chunk = b""
        if not chunk:
            self.stdin_open = False
            return False
        self.stdin_buf += chunk
        while b"\n" in self.stdin_buf:
            line, self.stdin_buf = self.stdin_buf.split(b"\n", 1)
            self.handle_line(line.decode("utf-8", "replace"), fd)
        return True

    def run_once(self, argv):
        """Runs argv on a PTY until it exits; None if stdin closed first."""
        pid, fd = spawn(argv, self.opts)
        emit({"t": "started", "pid": pid, "argv": argv})
        stdin_fd = sys.stdin.fileno()
        while True:
            timeout = None
            if self.pending:
                timeout = max(0.0, FLUSH_SECONDS - (time.monotonic() - self.pending_since))
            watch = [fd] + ([stdin_fd] if self.stdin_open else [])
            try:
                ready, _, _ = select.select(watch, [], [], timeout)
            except InterruptedError:
                continue
            if fd in ready:
                try:
                    data = os.read(fd, MAX_CHUNK)
                except OSError:
                    data = b""                # EIO: the child side closed
                if not data:
                    self.queue(self.decoder.decode(b"", final=True))
                    self.flush()
                    try:
                        os.close(fd)
                    except OSError:
                        pass
                    _, status = os.waitpid(pid, 0)
                    return exit_code(status)
                self.queue(self.decoder.decode(data))
            if stdin_fd in ready and not self.read_stdin(fd):
                self.flush()
                hang_up(pid, fd)
                return None
            if self.pending and (not ready or time.monotonic() - self.pending_since >= FLUSH_SECONDS):
                self.flush()

    def idle(self, seconds):
        """Waits between monitor runs, still answering resizes; False if stdin closed."""
        deadline = time.monotonic() + seconds
        stdin_fd = sys.stdin.fileno()
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                return True
            ready, _, _ = select.select([stdin_fd], [], [], left)
            if ready and not self.read_stdin(None):
                return False


def main(argv):
    if pty is None:
        emit({"t": "error", "msg": "pseudo-terminals are not available on this system"})
        return 2
    opts = parse_args(argv)
    if opts["require"] and shutil.which(opts["require"]) is None:
        emit({"t": "missing", "prog": opts["require"]})
        return 127
    if opts["cmd"]:
        target = ["/bin/sh", "-c", opts["cmd"]]
    else:
        target = [pick_shell(opts["shell"])]

    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    bridge = Bridge(opts)
    if opts["cmd"] and opts["repeat"] > 0:
        while True:
            emit({"t": "out", "d": "\x1b[H\x1b[2J"})
            code = bridge.run_once(target)
            if code is None:
                return 0
            if not bridge.idle(opts["repeat"]):
                return 0
    code = bridge.run_once(target)
    if code is None:
        return 0
    emit({"t": "exit", "code": code})
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (BrokenPipeError, KeyboardInterrupt):
        sys.exit(0)
