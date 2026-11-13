.pragma library

// A small xterm-compatible terminal emulator (no QML dependencies, so it is
// unit-tested with Node: install/tests/terminal_emulator_test.js).
//
//   var t = new Terminal(80, 24, { scrollback: 2000 });
//   t.onResponse = function (s) { /* write s back to the PTY */ };
//   t.write("\x1b[1;31mhello\x1b[0m\r\n");
//   t.lineCount(); t.line(abs); renderRow(t.line(abs), t.cols, theme)
//
// Supported: C0 controls, cursor movement, erase, insert/delete chars and
// lines, scroll regions, SGR (16/256/true colour, bold/dim/italic/underline/
// inverse/hidden/strike), alternate screen (47/1047/1049), cursor visibility
// and shape, application cursor keys, bracketed paste, DSR/DA replies, OSC
// titles, DEC line drawing, wide (CJK/emoji) characters, scrollback.
// Not supported (ignored safely): mouse reporting, sixel, reflow on resize.

var F_BOLD = 1, F_DIM = 2, F_ITALIC = 4, F_UNDERLINE = 8, F_BLINK = 16,
    F_INVERSE = 32, F_HIDDEN = 64, F_STRIKE = 128;
var TRUECOLOR = 0x1000000;

var DEC_GRAPHICS = {
    "`": "◆", "a": "▒", "f": "°", "g": "±", "j": "┘",
    "k": "┐", "l": "┌", "m": "└", "n": "┼", "o": "⎺",
    "p": "⎻", "q": "─", "r": "⎼", "s": "⎽", "t": "├",
    "u": "┤", "v": "┴", "w": "┬", "x": "│", "y": "≤",
    "z": "≥", "{": "π", "|": "≠", "}": "£", "~": "·"
};

var COMBINING = [
    [0x0300, 0x036F], [0x0483, 0x0489], [0x0591, 0x05BD], [0x0610, 0x061A],
    [0x064B, 0x065F], [0x0E31, 0x0E31], [0x0E34, 0x0E3A], [0x0E47, 0x0E4E],
    [0x1AB0, 0x1AFF], [0x1DC0, 0x1DFF], [0x200B, 0x200F], [0x20D0, 0x20FF],
    [0xFE00, 0xFE0F], [0xFE20, 0xFE2F], [0x1F3FB, 0x1F3FF], [0xE0100, 0xE01EF]
];
var WIDE = [
    [0x1100, 0x115F], [0x231A, 0x231B], [0x23E9, 0x23EC], [0x23F0, 0x23F0],
    [0x23F3, 0x23F3], [0x25FD, 0x25FE], [0x2614, 0x2615], [0x2648, 0x2653],
    [0x267F, 0x267F], [0x2693, 0x2693], [0x26A1, 0x26A1], [0x26AA, 0x26AB],
    [0x26BD, 0x26BE], [0x26C4, 0x26C5], [0x26CE, 0x26CE], [0x26D4, 0x26D4],
    [0x26EA, 0x26EA], [0x26F2, 0x26F3], [0x26F5, 0x26F5], [0x26FA, 0x26FA],
    [0x26FD, 0x26FD], [0x2705, 0x2705], [0x270A, 0x270B], [0x2728, 0x2728],
    [0x274C, 0x274C], [0x274E, 0x274E], [0x2753, 0x2755], [0x2757, 0x2757],
    [0x2795, 0x2797], [0x27B0, 0x27B0], [0x27BF, 0x27BF], [0x2B1B, 0x2B1C],
    [0x2B50, 0x2B50], [0x2B55, 0x2B55], [0x2E80, 0x303E], [0x3041, 0x33FF],
    [0x3400, 0x4DBF], [0x4E00, 0x9FFF], [0xA000, 0xA4CF], [0xAC00, 0xD7A3],
    [0xF900, 0xFAFF], [0xFE30, 0xFE4F], [0xFF00, 0xFF60], [0xFFE0, 0xFFE6],
    [0x1F004, 0x1F004], [0x1F0CF, 0x1F0CF], [0x1F18E, 0x1F18E], [0x1F191, 0x1F19A],
    [0x1F200, 0x1F2FF], [0x1F300, 0x1F64F], [0x1F680, 0x1F6FF], [0x1F900, 0x1F9FF],
    [0x1FA70, 0x1FAFF], [0x20000, 0x3FFFD]
];

function inRanges(cp, ranges) {
    var lo = 0, hi = ranges.length - 1;
    while (lo <= hi) {
        var mid = (lo + hi) >> 1;
        if (cp < ranges[mid][0]) hi = mid - 1;
        else if (cp > ranges[mid][1]) lo = mid + 1;
        else return true;
    }
    return false;
}

function charWidth(cp) {
    if (cp < 0x300) return 1;
    if (cp === 0x200D || inRanges(cp, COMBINING)) return 0;
    return inRanges(cp, WIDE) ? 2 : 1;
}

function blankCell(bg) {
    return { ch: " ", fg: -1, bg: bg === undefined ? -1 : bg, fl: 0, w: 1 };
}

function blankRow(cols, bg) {
    var cells = new Array(cols);
    for (var i = 0; i < cols; i++) cells[i] = blankCell(bg);
    return { cells: cells, wrapped: false };
}

function defaultAttr() { return { fg: -1, bg: -1, fl: 0 }; }

function isBlankRow(row) {
    for (var i = 0; i < row.cells.length; i++) {
        var c = row.cells[i];
        if (c.ch !== " " || c.bg !== -1) return false;
    }
    return true;
}

function Terminal(cols, rows, opts) {
    opts = opts || {};
    this.cols = Math.max(2, cols | 0);
    this.rows = Math.max(2, rows | 0);
    this.maxScrollback = opts.scrollback === undefined ? 2000 : Math.max(0, opts.scrollback | 0);
    this.onResponse = null;     // function(string): bytes to send back to the program
    this.onTitle = null;        // function(string)
    this.onBell = null;         // function()
    this.version = 0;
    this.reset();
}

Terminal.prototype.reset = function () {
    this.scrollback = [];
    this.lineBase = 0;          // lines dropped from the top of the scrollback so far
    this.pushed = 0;            // lines moved into the scrollback so far
    this.main = this._makeScreen();
    this.alt = this._makeScreen();
    this.screen = this.main;
    this.altActive = false;
    this.x = 0; this.y = 0;
    this.wrapPending = false;
    this.attr = defaultAttr();
    this.top = 0; this.bottom = this.rows - 1;
    this.autowrap = true;
    this.originMode = false;
    this.insertMode = false;
    this.appCursor = false;
    this.appKeypad = false;
    this.bracketedPaste = false;
    this.cursorVisible = true;
    this.cursorShape = "block";  // block | underline | bar
    this.cursorBlink = true;
    this.mouseMode = 0;
    this.charsets = ["B", "B"];
    this.gl = 0;
    this.saved = null;
    this.title = "";
    this.lastChar = "";
    this.tabs = this._defaultTabs(this.cols);
    this.state = 0;
    this.seq = "";
    this.version++;
};

Terminal.prototype._makeScreen = function () {
    var s = [];
    for (var i = 0; i < this.rows; i++) s.push(blankRow(this.cols));
    return s;
};

Terminal.prototype._defaultTabs = function (cols) {
    var t = {};
    for (var i = 8; i < cols; i += 8) t[i] = true;
    return t;
};

// ---- buffer access -----------------------------------------------------------

Terminal.prototype.scrollbackLength = function () {
    return this.altActive ? 0 : this.scrollback.length;
};

Terminal.prototype.lineCount = function () {
    return this.scrollbackLength() + this.rows;
};

Terminal.prototype.line = function (abs) {
    var sb = this.scrollbackLength();
    if (abs < 0) return null;
    if (abs < sb) return this.scrollback[abs];
    return this.screen[abs - sb] || null;
};

// Text between two positions { line: absolute line, col }; b.col is exclusive.
Terminal.prototype.textRange = function (a, b) {
    if (a.line > b.line || (a.line === b.line && a.col > b.col)) { var t = a; a = b; b = t; }
    var out = "";
    for (var l = a.line; l <= b.line; l++) {
        var row = this.line(l);
        if (!row) continue;
        var from = l === a.line ? a.col : 0;
        var to = l === b.line ? b.col : row.cells.length;
        var s = "";
        for (var c = Math.max(0, from); c < Math.min(to, row.cells.length); c++) s += row.cells[c].ch;
        if (l !== b.line) s = row.wrapped ? s : s.replace(/\s+$/, "") + "\n";
        else s = s.replace(/\s+$/, "");
        out += s;
    }
    return out;
};

Terminal.prototype.rowText = function (abs) {
    var row = this.line(abs);
    if (!row) return "";
    var s = "";
    for (var i = 0; i < row.cells.length; i++) s += row.cells[i].ch;
    return s.replace(/\s+$/, "");
};

// ---- resize (no reflow) ----------------------------------------------------------

Terminal.prototype.resize = function (cols, rows) {
    cols = Math.max(2, cols | 0); rows = Math.max(2, rows | 0);
    if (cols === this.cols && rows === this.rows) return;
    var screens = [this.main, this.alt];
    for (var si = 0; si < screens.length; si++) {
        var screen = screens[si];
        var active = screen === this.screen;
        var isMain = screen === this.main;
        for (var i = 0; i < screen.length; i++) {
            var cells = screen[i].cells;
            if (cells.length > cols) cells.length = cols;
            while (cells.length < cols) cells.push(blankCell());
        }
        var diff = screen.length - rows;
        if (diff > 0) {
            // drop blank rows below the cursor first, then move the top into the scrollback
            for (var r = screen.length - 1; r >= 0 && diff > 0; r--) {
                if (active && r <= this.y) break;
                if (!isBlankRow(screen[r])) break;
                screen.splice(r, 1);
                diff--;
            }
            if (diff > 0) {
                var gone = screen.splice(0, diff);
                if (isMain) this._pushScrollback(gone);
                if (active) this.y = Math.max(0, this.y - diff);
            }
        } else if (diff < 0) {
            var need = -diff;
            while (isMain && need > 0 && this.scrollback.length > 0) {
                var back = this.scrollback.pop();
                if (back.cells.length > cols) back.cells.length = cols;
                while (back.cells.length < cols) back.cells.push(blankCell());
                screen.unshift(back);
                need--;
                if (active) this.y++;
            }
            while (need-- > 0) screen.push(blankRow(cols));
        }
    }
    this.cols = cols; this.rows = rows;
    this.top = 0; this.bottom = rows - 1;
    this.x = Math.min(this.x, cols - 1);
    this.y = Math.min(this.y, rows - 1);
    this.wrapPending = false;
    this.tabs = this._defaultTabs(cols);
    this.version++;
};

// ---- low-level edits -------------------------------------------------------------

Terminal.prototype._pushScrollback = function (rows) {
    if (this.maxScrollback === 0) return;
    for (var i = 0; i < rows.length; i++) this.scrollback.push(rows[i]);
    this.pushed += rows.length;
    var over = this.scrollback.length - this.maxScrollback;
    if (over > 0) {
        this.scrollback.splice(0, over);
        this.lineBase += over;
    }
};

Terminal.prototype._scrollUp = function (n, toScrollback) {
    n = Math.max(1, Math.min(n, this.bottom - this.top + 1));
    var removed = this.screen.splice(this.top, n);
    for (var i = 0; i < n; i++) this.screen.splice(this.bottom - n + 1 + i, 0, blankRow(this.cols, this.attr.bg));
    if (toScrollback && this.top === 0 && !this.altActive) this._pushScrollback(removed);
};

Terminal.prototype._scrollDown = function (n) {
    n = Math.max(1, Math.min(n, this.bottom - this.top + 1));
    this.screen.splice(this.bottom - n + 1, n);
    for (var i = 0; i < n; i++) this.screen.splice(this.top, 0, blankRow(this.cols, this.attr.bg));
};

Terminal.prototype._index = function () {
    if (this.y === this.bottom) this._scrollUp(1, true);
    else if (this.y < this.rows - 1) this.y++;
};

Terminal.prototype._reverseIndex = function () {
    if (this.y === this.top) this._scrollDown(1);
    else if (this.y > 0) this.y--;
};

Terminal.prototype._eraseCells = function (row, from, to) {
    var cells = this.screen[row].cells;
    for (var i = Math.max(0, from); i < Math.min(to, this.cols); i++) cells[i] = blankCell(this.attr.bg);
};

Terminal.prototype._fixWideAt = function (cells, x) {
    // writing over half of a wide character clears the other half
    if (cells[x] && cells[x].w === 0 && x > 0) cells[x - 1] = blankCell(cells[x - 1].bg);
    if (cells[x] && cells[x].w === 2 && x + 1 < cells.length) cells[x + 1] = blankCell(cells[x + 1].bg);
};

Terminal.prototype._print = function (ch, cp) {
    if (this.charsets[this.gl] === "0" && DEC_GRAPHICS[ch]) ch = DEC_GRAPHICS[ch];
    var w = charWidth(cp);
    var cells;
    if (w === 0) {
        // combining mark: attach to the previous cell
        var px = this.wrapPending ? this.x : this.x - 1;
        cells = this.screen[this.y].cells;
        while (px > 0 && cells[px].w === 0) px--;
        if (px >= 0) cells[px].ch += ch;
        return;
    }
    if (this.wrapPending) {
        if (this.autowrap) {
            this.screen[this.y].wrapped = true;
            this.x = 0;
            this._index();
        }
        this.wrapPending = false;
    }
    if (w === 2 && this.x === this.cols - 1) {
        if (this.autowrap) {
            this._eraseCells(this.y, this.x, this.cols);
            this.screen[this.y].wrapped = true;
            this.x = 0;
            this._index();
        } else {
            w = 1;
        }
    }
    cells = this.screen[this.y].cells;
    if (this.insertMode) {
        for (var k = 0; k < w; k++) { cells.splice(this.x, 0, blankCell(this.attr.bg)); cells.pop(); }
    }
    this._fixWideAt(cells, this.x);
    if (w === 2) this._fixWideAt(cells, this.x + 1);
    var a = this.attr;
    cells[this.x] = { ch: ch, fg: a.fg, bg: a.bg, fl: a.fl, w: w };
    if (w === 2) cells[this.x + 1] = { ch: "", fg: a.fg, bg: a.bg, fl: a.fl, w: 0 };
    this.lastChar = ch;
    if (this.x + w >= this.cols) {
        this.x = this.cols - 1;
        if (this.autowrap) this.wrapPending = true;
    } else {
        this.x += w;
    }
};

// ---- parser ------------------------------------------------------------------
// states: 0 ground, 1 escape, 2 csi, 3 osc, 4 ignored string (dcs/apc/pm/sos),
//         5 one designator char (charsets, DECALN), 6 ESC inside a string

Terminal.prototype.write = function (data) {
    if (!data) return;
    for (var i = 0; i < data.length; i++) {
        var code = data.charCodeAt(i);
        var ch = data[i];
        if (code >= 0xD800 && code <= 0xDBFF && i + 1 < data.length) {
            var lo = data.charCodeAt(i + 1);
            if (lo >= 0xDC00 && lo <= 0xDFFF) {
                code = ((code - 0xD800) << 10) + (lo - 0xDC00) + 0x10000;
                ch = data[i] + data[i + 1];
                i++;
            }
        }
        this._feed(ch, code);
    }
    this.version++;
};

Terminal.prototype._feed = function (ch, code) {
    switch (this.state) {
    case 0:
        if (code === 0x1b) { this.state = 1; this.seq = ""; }
        else if (code < 0x20 || code === 0x7f) this._control(code);
        else this._print(ch, code);
        return;
    case 1:
        this._escape(ch, code);
        return;
    case 2:
        if (code === 0x1b) { this.state = 1; this.seq = ""; return; }
        if (code === 0x18 || code === 0x1a) { this.state = 0; return; }
        if (code < 0x20) { this._control(code); return; }
        if (code >= 0x40 && code <= 0x7e) {
            var seq = this.seq;
            this.state = 0;
            this._csi(seq, ch);
        } else {
            this.seq += ch;
            if (this.seq.length > 256) this.state = 0;   // runaway sequence
        }
        return;
    case 3:
        if (code === 0x07) { this._osc(this.seq); this.state = 0; return; }
        if (code === 0x1b) { this._osc(this.seq); this.state = 6; return; }
        this.seq += ch;
        if (this.seq.length > 4096) this.state = 4;
        return;
    case 4:
        if (code === 0x1b) this.state = 6;
        else if (code === 0x07) this.state = 0;
        return;
    case 5:
        if (this.seq === "(" || this.seq === ")") this.charsets[this.seq === "(" ? 0 : 1] = ch;
        else if (this.seq === "#" && ch === "8") this._alignmentTest();
        this.state = 0;
        return;
    case 6:
        // after ESC inside a string: "\" ends it, anything else starts a new escape
        if (ch === "\\") this.state = 0;
        else { this.state = 1; this.seq = ""; this._escape(ch, code); }
        return;
    }
};

Terminal.prototype._control = function (code) {
    switch (code) {
    case 0x07: if (this.onBell) this.onBell(); break;
    case 0x08:
        if (this.wrapPending) this.wrapPending = false;
        else if (this.x > 0) this.x--;
        break;
    case 0x09: this._tab(1); break;
    case 0x0a: case 0x0b: case 0x0c: this._index(); this.wrapPending = false; break;
    case 0x0d: this.x = 0; this.wrapPending = false; break;
    case 0x0e: this.gl = 1; break;
    case 0x0f: this.gl = 0; break;
    }
};

Terminal.prototype._tab = function (n) {
    while (n-- > 0) {
        var x = this.x + 1;
        while (x < this.cols - 1 && !this.tabs[x]) x++;
        this.x = Math.min(x, this.cols - 1);
    }
    this.wrapPending = false;
};

Terminal.prototype._backTab = function (n) {
    while (n-- > 0 && this.x > 0) {
        var x = this.x - 1;
        while (x > 0 && !this.tabs[x]) x--;
        this.x = x;
    }
    this.wrapPending = false;
};

Terminal.prototype._escape = function (ch, code) {
    if (code < 0x20 && code !== 0x1b) { this._control(code); return; }
    this.state = 0;
    var keepWrap = false;
    switch (ch) {
    case "[": this.state = 2; this.seq = ""; keepWrap = true; break;
    case "]": this.state = 3; this.seq = ""; keepWrap = true; break;
    case "P": case "X": case "^": case "_": this.state = 4; keepWrap = true; break;
    case "(": case ")": case "*": case "+": case "#": case "%": case " ":
        this.state = 5; this.seq = ch; keepWrap = true; break;
    case "7": this._saveCursor(); keepWrap = true; break;
    case "8": this._restoreCursor(); keepWrap = true; break;
    case "D": this._index(); break;
    case "E": this.x = 0; this._index(); break;
    case "M": this._reverseIndex(); break;
    case "H": this.tabs[this.x] = true; keepWrap = true; break;
    case "c": this.reset(); break;
    case "=": this.appKeypad = true; keepWrap = true; break;
    case ">": this.appKeypad = false; keepWrap = true; break;
    case "\x1b": this.state = 1; keepWrap = true; break;
    default: keepWrap = true;
    }
    if (!keepWrap) this.wrapPending = false;
};

Terminal.prototype._osc = function (s) {
    var semi = s.indexOf(";");
    if (semi < 0) return;
    var cmd = s.substring(0, semi);
    if (cmd === "0" || cmd === "2") {
        this.title = s.substring(semi + 1);
        if (this.onTitle) this.onTitle(this.title);
    }
};

Terminal.prototype._respond = function (s) {
    if (this.onResponse) this.onResponse(s);
};

Terminal.prototype._saveCursor = function () {
    this.saved = {
        x: this.x, y: this.y, wrapPending: this.wrapPending,
        attr: { fg: this.attr.fg, bg: this.attr.bg, fl: this.attr.fl },
        originMode: this.originMode, charsets: this.charsets.slice(), gl: this.gl
    };
};

Terminal.prototype._restoreCursor = function () {
    var s = this.saved;
    if (!s) { this.x = 0; this.y = 0; this.attr = defaultAttr(); this.wrapPending = false; return; }
    this.x = Math.min(s.x, this.cols - 1);
    this.y = Math.min(s.y, this.rows - 1);
    this.wrapPending = s.wrapPending;
    this.attr = { fg: s.attr.fg, bg: s.attr.bg, fl: s.attr.fl };
    this.originMode = s.originMode;
    this.charsets = s.charsets.slice();
    this.gl = s.gl;
};

Terminal.prototype._alignmentTest = function () {
    for (var r = 0; r < this.rows; r++)
        for (var c = 0; c < this.cols; c++) this.screen[r].cells[c] = { ch: "E", fg: -1, bg: -1, fl: 0, w: 1 };
};

Terminal.prototype._setAlt = function (on, clear) {
    if (on === this.altActive) return;
    this.altActive = on;
    this.screen = on ? this.alt : this.main;
    if (on && clear) {
        for (var r = 0; r < this.rows; r++) this.alt[r] = blankRow(this.cols);
    }
    this.top = 0; this.bottom = this.rows - 1;
};

Terminal.prototype._setMode = function (priv, params, on) {
    for (var i = 0; i < params.length; i++) {
        var p = params[i];
        if (priv) {
            switch (p) {
            case 1: this.appCursor = on; break;
            case 6: this.originMode = on; this.x = 0; this.y = on ? this.top : 0; break;
            case 7: this.autowrap = on; if (!on) this.wrapPending = false; break;
            case 12: this.cursorBlink = on; break;
            case 25: this.cursorVisible = on; break;
            case 47: case 1047: this._setAlt(on, on); break;
            case 1048: if (on) this._saveCursor(); else this._restoreCursor(); break;
            case 1049:
                if (on) { this._saveCursor(); this._setAlt(true, true); }
                else { this._setAlt(false, false); this._restoreCursor(); }
                break;
            case 1000: case 1002: case 1003: this.mouseMode = on ? p : 0; break;
            case 2004: this.bracketedPaste = on; break;
            }
        } else if (p === 4) {
            this.insertMode = on;
        }
    }
};

Terminal.prototype._sgr = function (raw) {
    // raw: parameter strings; colon sub-parameters (38:2::r:g:b) are flattened
    var p = [];
    for (var i = 0; i < raw.length; i++) {
        var parts = raw[i].split(":");
        if (parts.length > 1 && (parts[0] === "38" || parts[0] === "48" || parts[0] === "58")) {
            if (parts[1] === "2") {
                var rgb = parts.slice(parts.length >= 6 ? 3 : 2);
                p.push(parseInt(parts[0], 10), 2, parseInt(rgb[0], 10) || 0, parseInt(rgb[1], 10) || 0, parseInt(rgb[2], 10) || 0);
            } else {
                p.push(parseInt(parts[0], 10), 5, parseInt(parts[2], 10) || 0);
            }
        } else {
            p.push(raw[i] === "" ? 0 : (parseInt(parts[0], 10) || 0));
        }
    }
    if (p.length === 0) p = [0];
    var a = { fg: this.attr.fg, bg: this.attr.bg, fl: this.attr.fl };
    for (var k = 0; k < p.length; k++) {
        var v = p[k];
        if (v === 0) a = defaultAttr();
        else if (v === 1) a.fl |= F_BOLD;
        else if (v === 2) a.fl |= F_DIM;
        else if (v === 3) a.fl |= F_ITALIC;
        else if (v === 4 || v === 21) a.fl |= F_UNDERLINE;
        else if (v === 5 || v === 6) a.fl |= F_BLINK;
        else if (v === 7) a.fl |= F_INVERSE;
        else if (v === 8) a.fl |= F_HIDDEN;
        else if (v === 9) a.fl |= F_STRIKE;
        else if (v === 22) a.fl &= ~(F_BOLD | F_DIM);
        else if (v === 23) a.fl &= ~F_ITALIC;
        else if (v === 24) a.fl &= ~F_UNDERLINE;
        else if (v === 25) a.fl &= ~F_BLINK;
        else if (v === 27) a.fl &= ~F_INVERSE;
        else if (v === 28) a.fl &= ~F_HIDDEN;
        else if (v === 29) a.fl &= ~F_STRIKE;
        else if (v >= 30 && v <= 37) a.fg = v - 30;
        else if (v === 39) a.fg = -1;
        else if (v >= 40 && v <= 47) a.bg = v - 40;
        else if (v === 49) a.bg = -1;
        else if (v >= 90 && v <= 97) a.fg = v - 90 + 8;
        else if (v >= 100 && v <= 107) a.bg = v - 100 + 8;
        else if (v === 38 || v === 48 || v === 58) {
            var color;
            if (p[k + 1] === 5 && k + 2 < p.length) { color = p[k + 2] & 255; k += 2; }
            else if (p[k + 1] === 2 && k + 4 < p.length) {
                color = TRUECOLOR + (((p[k + 2] & 255) << 16) | ((p[k + 3] & 255) << 8) | (p[k + 4] & 255));
                k += 4;
            } else break;
            if (v === 38) a.fg = color;
            else if (v === 48) a.bg = color;
        }
    }
    this.attr = a;
};

Terminal.prototype._csi = function (seq, final) {
    var prefix = "";
    if (seq.length && "?<=>".indexOf(seq[0]) >= 0) { prefix = seq[0]; seq = seq.substring(1); }
    var inter = "";
    while (seq.length && seq.charCodeAt(seq.length - 1) >= 0x20 && seq.charCodeAt(seq.length - 1) <= 0x2f) {
        inter = seq[seq.length - 1] + inter;
        seq = seq.substring(0, seq.length - 1);
    }
    var raw = seq === "" ? [] : seq.split(";");
    var params = raw.map(function (s) { return s === "" ? 0 : (parseInt(s, 10) || 0); });
    function P(i, def) { return params[i] ? params[i] : def; }
    var n, r, q;

    if (inter === " " && final === "q") {
        var shape = P(0, 1);
        this.cursorShape = shape <= 2 ? "block" : (shape <= 4 ? "underline" : "bar");
        this.cursorBlink = shape === 0 || shape % 2 === 1;
        return;
    }
    if (inter === "!" && final === "p") {      // DECSTR soft reset
        this.attr = defaultAttr(); this.top = 0; this.bottom = this.rows - 1;
        this.cursorVisible = true; this.insertMode = false; this.originMode = false;
        this.autowrap = true; this.appCursor = false; this.wrapPending = false;
        return;
    }
    if (inter !== "") return;
    if (final !== "m" && final !== "h" && final !== "l" && final !== "b" && final !== "n" && final !== "c") this.wrapPending = false;

    switch (final) {
    case "A": this.y = Math.max(this.y >= this.top ? this.top : 0, this.y - P(0, 1)); break;
    case "B": this.y = Math.min(this.y <= this.bottom ? this.bottom : this.rows - 1, this.y + P(0, 1)); break;
    case "C": case "a": this.x = Math.min(this.cols - 1, this.x + P(0, 1)); break;
    case "D": this.x = Math.max(0, this.x - P(0, 1)); break;
    case "E": this.x = 0; this.y = Math.min(this.rows - 1, this.y + P(0, 1)); break;
    case "F": this.x = 0; this.y = Math.max(0, this.y - P(0, 1)); break;
    case "G": case "`": this.x = Math.min(this.cols - 1, P(0, 1) - 1); break;
    case "d": this.y = Math.min(this.rows - 1, (this.originMode ? this.top : 0) + P(0, 1) - 1); break;
    case "e": this.y = Math.min(this.rows - 1, this.y + P(0, 1)); break;
    case "H": case "f":
        this.y = Math.min(this.originMode ? this.bottom : this.rows - 1, (this.originMode ? this.top : 0) + P(0, 1) - 1);
        this.x = Math.min(this.cols - 1, P(1, 1) - 1);
        break;
    case "J":
        n = params[0] || 0;
        if (n === 0) {
            this._eraseCells(this.y, this.x, this.cols);
            for (r = this.y + 1; r < this.rows; r++) this.screen[r] = blankRow(this.cols, this.attr.bg);
        } else if (n === 1) {
            for (r = 0; r < this.y; r++) this.screen[r] = blankRow(this.cols, this.attr.bg);
            this._eraseCells(this.y, 0, this.x + 1);
        } else if (n === 2) {
            for (r = 0; r < this.rows; r++) this.screen[r] = blankRow(this.cols, this.attr.bg);
        } else if (n === 3) {
            this.lineBase += this.scrollback.length;
            this.scrollback = [];
        }
        break;
    case "K":
        n = params[0] || 0;
        if (n === 0) this._eraseCells(this.y, this.x, this.cols);
        else if (n === 1) this._eraseCells(this.y, 0, this.x + 1);
        else if (n === 2) this._eraseCells(this.y, 0, this.cols);
        this.screen[this.y].wrapped = false;
        break;
    case "L":
        if (this.y >= this.top && this.y <= this.bottom) {
            n = Math.min(P(0, 1), this.bottom - this.y + 1);
            this.screen.splice(this.bottom - n + 1, n);
            for (q = 0; q < n; q++) this.screen.splice(this.y, 0, blankRow(this.cols, this.attr.bg));
            this.x = 0;
        }
        break;
    case "M":
        if (this.y >= this.top && this.y <= this.bottom) {
            n = Math.min(P(0, 1), this.bottom - this.y + 1);
            this.screen.splice(this.y, n);
            for (q = 0; q < n; q++) this.screen.splice(this.bottom - n + 1 + q, 0, blankRow(this.cols, this.attr.bg));
            this.x = 0;
        }
        break;
    case "@":
        n = Math.min(P(0, 1), this.cols - this.x);
        var ic = this.screen[this.y].cells;
        for (q = 0; q < n; q++) { ic.splice(this.x, 0, blankCell(this.attr.bg)); ic.pop(); }
        break;
    case "P":
        n = Math.min(P(0, 1), this.cols - this.x);
        var dc = this.screen[this.y].cells;
        dc.splice(this.x, n);
        for (q = 0; q < n; q++) dc.push(blankCell(this.attr.bg));
        break;
    case "X": this._eraseCells(this.y, this.x, this.x + P(0, 1)); break;
    case "S": if (prefix === "") this._scrollUp(P(0, 1), false); break;
    case "T": if (prefix === "") this._scrollDown(P(0, 1)); break;
    case "I": this._tab(P(0, 1)); break;
    case "Z": this._backTab(P(0, 1)); break;
    case "b":
        if (this.lastChar) {
            n = Math.min(P(0, 1), 65535);
            var cp = this.lastChar.codePointAt(0);
            for (q = 0; q < n; q++) this._print(this.lastChar, cp);
        }
        break;
    case "g":
        if ((params[0] || 0) === 0) delete this.tabs[this.x];
        else if (params[0] === 3) this.tabs = {};
        break;
    case "r":
        if (prefix === "") {
            var t = P(0, 1) - 1, b = P(1, this.rows) - 1;
            if (t < b && b < this.rows) { this.top = t; this.bottom = b; }
            else { this.top = 0; this.bottom = this.rows - 1; }
            this.x = 0; this.y = this.originMode ? this.top : 0;
        }
        break;
    case "s": if (prefix === "") this._saveCursor(); break;
    case "u": if (prefix === "") this._restoreCursor(); break;
    case "m": if (prefix === "") this._sgr(raw); break;
    case "h": this._setMode(prefix === "?", params, true); break;
    case "l": this._setMode(prefix === "?", params, false); break;
    case "n":
        if (params[0] === 5) this._respond("\x1b[0n");
        else if (params[0] === 6) this._respond("\x1b[" + (prefix === "?" ? "?" : "") + (this.y + 1) + ";" + (this.x + 1) + "R");
        break;
    case "c":
        if (prefix === ">") this._respond("\x1b[>0;10;1c");
        else if (prefix === "" && (params[0] || 0) === 0) this._respond("\x1b[?62;22c");
        break;
    }
};

// ---- rendering helpers -------------------------------------------------------------

function hex2(v) { var s = (v & 255).toString(16); return s.length < 2 ? "0" + s : s; }
function hex3(r, g, b) { return "#" + hex2(r) + hex2(g) + hex2(b); }

var XTERM_256 = (function () {
    var t = [];
    var steps = [0, 95, 135, 175, 215, 255];
    for (var i = 0; i < 16; i++) t.push(null);           // the theme's 16 colours
    for (var r = 0; r < 6; r++) for (var g = 0; g < 6; g++) for (var b = 0; b < 6; b++)
        t.push(hex3(steps[r], steps[g], steps[b]));
    for (var s = 0; s < 24; s++) { var v = 8 + s * 10; t.push(hex3(v, v, v)); }
    return t;
})();

function colorOf(c, theme) {
    if (c < 0) return null;
    if (c < 16) return theme.palette[c];
    if (c < 256) return XTERM_256[c];
    var v = c - TRUECOLOR;
    return hex3((v >> 16) & 255, (v >> 8) & 255, v & 255);
}

function escapeHtml(s) {
    var out = "";
    for (var i = 0; i < s.length; i++) {
        var c = s[i];
        if (c === "&") out += "&amp;";
        else if (c === "<") out += "&lt;";
        else if (c === ">") out += "&gt;";
        else if (c === " ") out += "&nbsp;";
        else out += c;
    }
    return out;
}

// Effective colours of one cell: { fg: "#rrggbb" or "#aarrggbb", bg: "#rrggbb" | null }
// theme: { fg, bg, palette: [16 colours "#rrggbb"], boldBright }
function cellColors(cell, theme) {
    var fgIdx = cell.fg;
    if ((cell.fl & F_BOLD) && theme.boldBright !== false && fgIdx >= 0 && fgIdx < 8) fgIdx += 8;
    var fg = colorOf(fgIdx, theme) || theme.fg;
    var bg = colorOf(cell.bg, theme);
    if (cell.fl & F_INVERSE) {
        var nf = bg || theme.bg;
        bg = fg;
        fg = nf;
    }
    if (cell.fl & F_HIDDEN) fg = bg || theme.bg;
    if ((cell.fl & F_DIM) && fg.length === 7) fg = "#99" + fg.substring(1);
    return { fg: fg, bg: bg };
}

// One row as positioned StyledText segments and background runs:
//   { segs: [{ col, html }], bgs: [{ col, len, color }] }
// Segments break only around wide characters, so a fallback font for
// CJK/emoji cannot push the rest of the row off the grid.
function renderRow(row, cols, theme) {
    var out = { segs: [], bgs: [] };
    if (!row) return out;
    var cells = row.cells;
    var n = Math.min(cols, cells.length);
    var last = n - 1;
    while (last >= 0 && cells[last].ch === " " && cells[last].bg === -1
           && !(cells[last].fl & (F_INVERSE | F_UNDERLINE | F_STRIKE))) last--;

    var seg = null, run = "", runKey = "", runOpen = "", runClose = "", bgRun = null;
    function closeRun() {
        if (run !== "" && seg) seg.html += runOpen + run + runClose;
        run = ""; runKey = "";
    }
    function closeSeg() {
        closeRun();
        if (seg && seg.html !== "") out.segs.push(seg);
        seg = null;
    }
    for (var x = 0; x <= last; x++) {
        var cell = cells[x];
        if (cell.w === 0) continue;
        var col = cellColors(cell, theme);
        if (col.bg) {
            if (bgRun && bgRun.color === col.bg && bgRun.col + bgRun.len === x) bgRun.len += cell.w;
            else { bgRun = { col: x, len: cell.w, color: col.bg }; out.bgs.push(bgRun); }
        }
        if (cell.w === 2) closeSeg();
        if (!seg) seg = { col: x, html: "" };
        var key = col.fg + "|" + (cell.fl & (F_BOLD | F_ITALIC | F_UNDERLINE | F_STRIKE));
        if (key !== runKey) {
            closeRun();
            runKey = key;
            runOpen = ""; runClose = "";
            if (col.fg !== theme.fg) { runOpen += '<font color="' + col.fg + '">'; runClose = "</font>" + runClose; }
            if (cell.fl & F_BOLD) { runOpen += "<b>"; runClose = "</b>" + runClose; }
            if (cell.fl & F_ITALIC) { runOpen += "<i>"; runClose = "</i>" + runClose; }
            if (cell.fl & F_UNDERLINE) { runOpen += "<u>"; runClose = "</u>" + runClose; }
            if (cell.fl & F_STRIKE) { runOpen += "<s>"; runClose = "</s>" + runClose; }
        }
        run += escapeHtml(cell.ch === "" ? " " : cell.ch);
        if (cell.w === 2) closeSeg();
    }
    closeSeg();
    return out;
}

// ---- keyboard ------------------------------------------------------------------
// Qt key codes and modifier flags (values of Qt::Key / Qt::KeyboardModifier).
var K = {
    Escape: 0x01000000, Tab: 0x01000001, Backtab: 0x01000002, Backspace: 0x01000003,
    Return: 0x01000004, Enter: 0x01000005, Insert: 0x01000006, Delete: 0x01000007,
    Home: 0x01000010, End: 0x01000011, Left: 0x01000012, Up: 0x01000013,
    Right: 0x01000014, Down: 0x01000015, PageUp: 0x01000016, PageDown: 0x01000017,
    F1: 0x01000030, F12: 0x0100003b, Space: 0x20
};
var M_SHIFT = 0x02000000, M_CTRL = 0x04000000, M_ALT = 0x08000000;

// Bytes a key press sends to the program ("" when it sends nothing).
function keySequence(key, text, mods, appCursor) {
    var shift = !!(mods & M_SHIFT), ctrl = !!(mods & M_CTRL), alt = !!(mods & M_ALT);
    var m = 1 + (shift ? 1 : 0) + (alt ? 2 : 0) + (ctrl ? 4 : 0);
    var cursorKey = key === K.Up ? "A" : key === K.Down ? "B" : key === K.Right ? "C"
        : key === K.Left ? "D" : key === K.Home ? "H" : key === K.End ? "F" : "";
    if (cursorKey !== "") {
        if (m > 1) return "\x1b[1;" + m + cursorKey;
        return (appCursor ? "\x1bO" : "\x1b[") + cursorKey;
    }
    var tilde = key === K.Insert ? 2 : key === K.Delete ? 3 : key === K.PageUp ? 5 : key === K.PageDown ? 6 : 0;
    if (tilde) return "\x1b[" + tilde + (m > 1 ? ";" + m : "") + "~";
    if (key >= K.F1 && key <= K.F12) {
        var f = key - K.F1;
        if (f < 4) return m > 1 ? "\x1b[1;" + m + "PQRS"[f] : "\x1bO" + "PQRS"[f];
        var codes = [15, 17, 18, 19, 20, 21, 23, 24];
        return "\x1b[" + codes[f - 4] + (m > 1 ? ";" + m : "") + "~";
    }
    var prefix = alt ? "\x1b" : "";
    switch (key) {
    case K.Escape: return "\x1b";
    case K.Return: case K.Enter: return prefix + "\r";
    case K.Backspace: return prefix + (ctrl ? "\x08" : "\x7f");
    case K.Tab: return shift ? "\x1b[Z" : prefix + "\t";
    case K.Backtab: return "\x1b[Z";
    }
    if (ctrl) {
        if (key >= 0x41 && key <= 0x5a) return prefix + String.fromCharCode(key - 0x40);
        if (key === K.Space || key === 0x40 || key === 0x32) return prefix + "\x00";
        if (key === 0x5b || key === 0x33) return "\x1b";
        if (key === 0x5c || key === 0x34) return prefix + "\x1c";
        if (key === 0x5d || key === 0x35) return prefix + "\x1d";
        if (key === 0x5e || key === 0x36) return prefix + "\x1e";
        if (key === 0x5f || key === 0x2d || key === 0x2f || key === 0x37) return prefix + "\x1f";
        if (text && text.length === 1 && text.charCodeAt(0) < 0x20) return prefix + text;
        return "";
    }
    if (text && text.length > 0) {
        if (text.charCodeAt(0) === 0x7f) return "";
        return prefix + text;
    }
    return "";
}

// Text pasted into the program; bracketed when the program asked for it, and
// with any embedded end-of-paste marker removed so a paste cannot escape it.
function pasteSequence(text, bracketed) {
    var t = String(text).replace(/\r?\n/g, "\r");
    if (bracketed) t = "\x1b[200~" + t.replace(/\x1b\[20[01]~/g, "") + "\x1b[201~";
    return t;
}

// Node (tests) export; QML ignores this block.
if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        Terminal: Terminal, renderRow: renderRow, keySequence: keySequence,
        pasteSequence: pasteSequence, charWidth: charWidth, cellColors: cellColors,
        K: K, M_SHIFT: M_SHIFT, M_CTRL: M_CTRL, M_ALT: M_ALT, TRUECOLOR: TRUECOLOR
    };
}
