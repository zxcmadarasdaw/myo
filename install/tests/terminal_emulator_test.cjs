// Desktop Terminal widget: emulator core (src/quickshell/widgets/faces/terminal/TerminalEmulator.js).
//
//     node install/tests/terminal_emulator_test.cjs
//
// Feeds real escape sequences (what bash, readline, vim, htop, fastfetch and
// cmatrix emit) into the emulator and checks the screen, scrollback, modes,
// replies, rendering and key encoding. The PTY bridge is tested separately
// (install/tests/terminal_pty_test.py, Linux only).
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');

function library(file) {
    const context = {module: {exports: {}}};
    vm.runInNewContext(fs.readFileSync(path.resolve(__dirname, '../../', file), 'utf8').replace(/^\.pragma library\s*/, ''), context);
    return context.module.exports;
}
const V = library('src/quickshell/widgets/faces/terminal/TerminalEmulator.js');

let passed = 0;
function test(name, fn) {
    try { fn(); passed++; console.log('PASS', name); }
    catch (e) { console.error('FAIL', name); throw e; }
}
const sb = t => t.scrollbackLength();
const screenText = t => { const out = []; for (let i = 0; i < t.rows; i++) out.push(t.rowText(sb(t) + i)); return out; };
const hex = i => i.toString(16);
const theme = { fg: '#cdd6f4', bg: '#1e1e2e', palette: Array.from({length: 16}, (_, i) => '#0000' + hex(i) + hex(i)), boldBright: true };

test('plain text, CR/LF and wrapping', () => {
    const t = new V.Terminal(10, 3);
    t.write('hello\r\nworld');
    assert.deepEqual(screenText(t), ['hello', 'world', '']);
    t.write('\r\n0123456789AB');
    assert.equal(t.scrollbackLength(), 1);                 // "hello" scrolled off
    assert.equal(t.scrollback[0].cells.map(c => c.ch).join('').trim(), 'hello');
    assert.deepEqual(screenText(t), ['world', '0123456789', 'AB']);
    assert.equal(t.line(sb(t) + 1).wrapped, true);
});

test('pending wrap: a full line followed by CRLF does not add a blank line', () => {
    const t = new V.Terminal(5, 3);
    t.write('abcde\r\nf');
    assert.deepEqual(screenText(t), ['abcde', 'f', '']);
});

test('cursor movement, erase in line/display', () => {
    const t = new V.Terminal(10, 3);
    t.write('aaaaaaaaaa\r\nbbbbbbbbbb\r\ncccccccccc');
    t.write('\x1b[2;3H\x1b[K');
    assert.equal(t.rowText(1), 'bb');
    t.write('\x1b[1;5H\x1b[1K');
    assert.equal(t.rowText(0), '     aaaaa');
    t.write('\x1b[2J');
    assert.deepEqual(screenText(t), ['', '', '']);
    t.write('\x1b[3;10Hz');
    assert.equal(t.rowText(2), '         z');
    t.write('\x1b[1;1H\x1b[5Cq\x1b[3Dr');
    assert.equal(t.rowText(0), '   r q');
});

test('backspace editing like readline', () => {
    const t = new V.Terminal(20, 2);
    t.write('$ lss\x08 \x08');
    assert.equal(t.rowText(0), '$ ls');
    assert.equal(t.x, 4);
});

test('tabs', () => {
    const t = new V.Terminal(20, 2);
    t.write('a\tb\tc');
    assert.equal(t.rowText(0), 'a       b       c');
});

test('SGR colours: 16, 256, truecolor, colon form, reset', () => {
    const t = new V.Terminal(20, 2);
    t.write('\x1b[1;31mR\x1b[0m\x1b[38;5;208mO\x1b[38;2;10;20;30mT\x1b[38:2::1:2:3mC\x1b[48;5;21;4mU\x1b[mN');
    const c = t.line(0).cells;
    assert.equal(c[0].fg, 1); assert.ok(c[0].fl & 1);
    assert.equal(c[1].fg, 208);
    assert.equal(c[2].fg, V.TRUECOLOR + (10 << 16 | 20 << 8 | 30));
    assert.equal(c[3].fg, V.TRUECOLOR + (1 << 16 | 2 << 8 | 3));
    assert.equal(c[4].bg, 21); assert.ok(c[4].fl & 8);
    assert.equal(c[5].fg, -1); assert.equal(c[5].bg, -1); assert.equal(c[5].fl, 0);
    t.write('\x1b[94;103mB');
    assert.equal(t.line(0).cells[6].fg, 12);
    assert.equal(t.line(0).cells[6].bg, 11);
});

test('scroll region (vim/less style) does not touch lines outside it', () => {
    const t = new V.Terminal(5, 5);
    t.write('1\r\n2\r\n3\r\n4\r\n5');
    t.write('\x1b[2;4r\x1b[4;1H\n');                     // LF at the bottom margin
    assert.deepEqual(screenText(t), ['1', '3', '4', '', '5']);
    assert.equal(t.scrollbackLength(), 0);               // region scrolls never feed the scrollback
    t.write('\x1b[2;1H\x1bM');                            // reverse index at the top margin
    assert.deepEqual(screenText(t), ['1', '', '3', '4', '5']);
    t.write('\x1b[r');
    assert.equal(t.top, 0); assert.equal(t.bottom, 4);
});

test('insert/delete lines and characters', () => {
    const t = new V.Terminal(6, 4);
    t.write('aaa\r\nbbb\r\nccc\r\nddd');
    t.write('\x1b[2;1H\x1b[L');
    assert.deepEqual(screenText(t), ['aaa', '', 'bbb', 'ccc']);
    t.write('\x1b[M');
    assert.deepEqual(screenText(t), ['aaa', 'bbb', 'ccc', '']);
    t.write('\x1b[1;1H\x1b[2@X');
    assert.equal(t.rowText(0), 'X aaa');
    t.write('\x1b[1;1H\x1b[2P');
    assert.equal(t.rowText(0), 'aaa');
    t.write('\x1b[1;2H\x1b[1X');
    assert.equal(t.rowText(0), 'a a');
});

test('alternate screen keeps the shell screen and cursor (1049)', () => {
    const t = new V.Terminal(10, 3);
    t.write('prompt$ ');
    t.write('\x1b[?1049h\x1b[H\x1b[2Jfullscreen');
    assert.equal(t.altActive, true);
    assert.equal(t.rowText(0), 'fullscreen');
    assert.equal(t.lineCount(), 3);                       // no scrollback on the alt screen
    t.write('\x1b[?1049l');
    assert.equal(t.altActive, false);
    assert.equal(t.rowText(sb(t)), 'prompt$');
    assert.equal(t.x, 8);
});

test('modes: cursor visibility, app cursor keys, bracketed paste, cursor shape', () => {
    const t = new V.Terminal(10, 3);
    t.write('\x1b[?25l\x1b[?1h\x1b[?2004h\x1b[5 q');
    assert.equal(t.cursorVisible, false);
    assert.equal(t.appCursor, true);
    assert.equal(t.bracketedPaste, true);
    assert.equal(t.cursorShape, 'bar');
    t.write('\x1b[?25h\x1b[?1l\x1b[?2004l\x1b[2 q');
    assert.equal(t.cursorVisible, true);
    assert.equal(t.appCursor, false);
    assert.equal(t.bracketedPaste, false);
    assert.equal(t.cursorShape, 'block');
});

test('DSR / DA replies go to onResponse', () => {
    const t = new V.Terminal(10, 5);
    const replies = [];
    t.onResponse = s => replies.push(s);
    t.write('\x1b[3;4H\x1b[6n\x1b[5n\x1b[c\x1b[>c');
    assert.deepEqual(replies, ['\x1b[3;4R', '\x1b[0n', '\x1b[?62;22c', '\x1b[>0;10;1c']);
});

test('OSC title (BEL and ST), unknown OSC/DCS swallowed', () => {
    const t = new V.Terminal(20, 2);
    let title = '';
    t.onTitle = s => { title = s; };
    t.write('\x1b]0;user@host: ~\x07a\x1b]2;vim\x1b\\b\x1b]7;file://h/p\x07\x1bPq#0;2;0;0;0\x1b\\c');
    assert.equal(title, 'vim');
    assert.equal(t.rowText(0), 'abc');
});

test('DEC line drawing (ncurses boxes)', () => {
    const t = new V.Terminal(10, 2);
    t.write('\x1b(0lqqk\x1b(B x');
    assert.equal(t.rowText(0), '┌──┐ x');
});

test('wide characters and combining marks', () => {
    const t = new V.Terminal(6, 2);
    t.write('a中b');
    const c = t.line(0).cells;
    assert.equal(c[1].ch, '中'); assert.equal(c[1].w, 2);
    assert.equal(c[2].w, 0);
    assert.equal(c[3].ch, 'b');
    assert.equal(t.x, 4);
    t.write('\r\né');
    assert.equal(t.line(1).cells[0].ch, 'é');
    assert.equal(t.x, 1);
    const t2 = new V.Terminal(4, 2);
    t2.write('abc\u{1F600}');                            // no room in the last column: wraps
    assert.equal(t2.rowText(0), 'abc');
    assert.equal(t2.line(1).cells[0].ch, '\u{1F600}');
});

test('escape sequences split across writes', () => {
    const t = new V.Terminal(10, 2);
    t.write('\x1b[3');
    t.write('1mr\x1b');
    t.write('[0mx');
    assert.equal(t.line(0).cells[0].fg, 1);
    assert.equal(t.line(0).cells[1].fg, -1);
    assert.equal(t.rowText(0), 'rx');
});

test('scrollback limit and lineBase', () => {
    const t = new V.Terminal(5, 2, { scrollback: 3 });
    for (let i = 0; i < 10; i++) t.write(i + '\r\n');
    assert.equal(t.scrollbackLength(), 3);
    assert.equal(t.lineBase, 6);
    assert.equal(t.rowText(0), '6');
    t.write('\x1b[3J');
    assert.equal(t.scrollbackLength(), 0);
});

test('resize keeps the cursor line and uses the scrollback', () => {
    const t = new V.Terminal(10, 4);
    t.write('1\r\n2\r\n3\r\n$ ');
    t.resize(10, 2);
    assert.deepEqual(screenText(t), ['3', '$']);
    assert.equal(t.y, 1);
    t.resize(10, 4);
    assert.deepEqual(screenText(t), ['1', '2', '3', '$']);
    t.resize(4, 4);
    assert.equal(t.line(sb(t)).cells.length, 4);
    assert.ok(t.x <= 3);
});

test('selection text joins wrapped lines and trims padding', () => {
    const t = new V.Terminal(5, 4);
    t.write('abcdefg\r\nxy   \r\nz');
    // 5 columns: "abcdefg" occupies rows 0-1 (row 0 wrapped), "xy" row 2, "z" row 3
    assert.equal(t.textRange({ line: 0, col: 0 }, { line: 3, col: 5 }), 'abcdefg\nxy\nz');
    assert.equal(t.textRange({ line: 0, col: 2 }, { line: 0, col: 4 }), 'cd');
    assert.equal(t.textRange({ line: 0, col: 4 }, { line: 0, col: 2 }), 'cd');   // reversed drag
});

test('REP repeats the last character; soft reset', () => {
    const t = new V.Terminal(10, 2);
    t.write('-\x1b[4b');
    assert.equal(t.rowText(0), '-----');
    t.write('\x1b[?25l\x1b[1m\x1b[!p');
    assert.equal(t.cursorVisible, true);
    assert.equal(t.attr.fl, 0);
});

test('garbage and runaway sequences never throw or leave the grid', () => {
    const t = new V.Terminal(8, 3);
    let s = '';
    for (let i = 0; i < 5000; i++) s += String.fromCharCode((i * 7919) % 0x2600);
    t.write(s);
    t.write('\x1b[' + '9'.repeat(400) + 'm\x1b[999;999H\x1b[99999@\x1b[-1;-1r\x1b[99999L\x1b[99999M');
    assert.equal(t.rows, 3);
    assert.equal(t.screen.length, 3);
    assert.ok(t.screen.every(r => r.cells.length === 8));
    assert.ok(t.x < 8 && t.y < 3);
});

test('renderRow: segments, colours, escaping, backgrounds, wide chars', () => {
    const t = new V.Terminal(12, 2);
    t.write('a<&\x1b[31mR\x1b[1mB\x1b[0m\x1b[44m  \x1b[0m中z');
    const r = V.renderRow(t.line(0), t.cols, theme);
    assert.equal(r.segs[0].col, 0);
    assert.ok(r.segs[0].html.startsWith('a&lt;&amp;'));
    assert.ok(r.segs[0].html.includes('<font color="' + theme.palette[1] + '">R</font>'));
    assert.ok(r.segs[0].html.includes('<font color="' + theme.palette[9] + '"><b>B</b></font>'), 'bold red uses bright red');
    assert.ok(r.segs[0].html.includes('&nbsp;&nbsp;'));
    assert.equal(JSON.stringify(r.bgs), JSON.stringify([{ col: 5, len: 2, color: theme.palette[4] }]));   // vm realm: compare as JSON
    assert.equal(r.segs[1].col, 7); assert.equal(r.segs[1].html, '中');
    assert.equal(r.segs[2].col, 9); assert.equal(r.segs[2].html, 'z');
    const inv = V.cellColors({ ch: 'x', fg: -1, bg: -1, fl: 32, w: 1 }, theme);
    assert.equal(inv.fg, theme.bg); assert.equal(inv.bg, theme.fg);
    assert.equal(V.cellColors({ ch: 'x', fg: 196, bg: -1, fl: 0, w: 1 }, theme).fg, '#ff0000');
    assert.equal(V.cellColors({ ch: 'x', fg: 232, bg: -1, fl: 0, w: 1 }, theme).fg, '#080808');
    assert.equal(V.cellColors({ ch: 'x', fg: -1, bg: -1, fl: 2, w: 1 }, theme).fg, '#99cdd6f4');
    assert.equal(JSON.stringify(V.renderRow(new V.Terminal(4, 2).line(0), 4, theme)), '{"segs":[],"bgs":[]}');
});

test('keySequence: printable, control, cursor/function keys, modifiers', () => {
    const K = V.K;
    assert.equal(V.keySequence(0x41, 'a', 0, false), 'a');
    assert.equal(V.keySequence(0x43, 'c', V.M_CTRL, false), '\x03');
    assert.equal(V.keySequence(0x44, '\x04', V.M_CTRL, false), '\x04');
    assert.equal(V.keySequence(0x42, 'b', V.M_ALT, false), '\x1bb');
    assert.equal(V.keySequence(K.Return, '\r', 0, false), '\r');
    assert.equal(V.keySequence(K.Backspace, '\x08', 0, false), '\x7f');
    assert.equal(V.keySequence(K.Tab, '\t', 0, false), '\t');
    assert.equal(V.keySequence(K.Backtab, '', V.M_SHIFT, false), '\x1b[Z');
    assert.equal(V.keySequence(K.Up, '', 0, false), '\x1b[A');
    assert.equal(V.keySequence(K.Up, '', 0, true), '\x1bOA');
    assert.equal(V.keySequence(K.Right, '', V.M_CTRL, false), '\x1b[1;5C');
    assert.equal(V.keySequence(K.Delete, '', 0, false), '\x1b[3~');
    assert.equal(V.keySequence(K.PageUp, '', V.M_SHIFT, false), '\x1b[5;2~');
    assert.equal(V.keySequence(K.F1, '', 0, false), '\x1bOP');
    assert.equal(V.keySequence(K.F1 + 4, '', 0, false), '\x1b[15~');
    assert.equal(V.keySequence(K.F12, '', 0, false), '\x1b[24~');
    assert.equal(V.keySequence(K.Escape, '\x1b', 0, false), '\x1b');
    assert.equal(V.keySequence(0x20, ' ', V.M_CTRL, false), '\x00');
    assert.equal(V.keySequence(0x01000020, '', V.M_SHIFT, false), '');   // Shift alone sends nothing
    assert.equal(V.keySequence(0x416, 'ж', 0, false), 'ж');      // Cyrillic text passes through
});

test('pasteSequence: newlines become CR, bracketed paste cannot be escaped', () => {
    assert.equal(V.pasteSequence('a\nb\r\nc', false), 'a\rb\rc');
    assert.equal(V.pasteSequence('x\x1b[201~rm -rf ~\n', true), '\x1b[200~xrm -rf ~\r\x1b[201~');
});

console.log(`terminal_emulator_test: ${passed} passed`);
