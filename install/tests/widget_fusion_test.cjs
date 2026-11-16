const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function library(name, globals = {}) {
    const source = fs.readFileSync(path.resolve(__dirname, '../../src/quickshell/widgets/canvas', name), 'utf8');
    const context = vm.createContext(globals);
    vm.runInContext(source.replace(/^\.(?:pragma|import).*$/gm, ''), context);
    return context;
}

const CM = library('CanvasMath.js');
const Fusion = library('WidgetFusion.js', {CM});
const members = [
    {wId: 'a', wType: 'cpu', wX: -200, wY: 60, wWidth: 120, wHeight: 80, wRotation: 0},
    {wId: 'b', wType: 'ram', wX: -70, wY: 60, wWidth: 80, wHeight: 120, wRotation: 90},
    {wId: 'c', wType: 'weather', wX: -200, wY: 150, wWidth: 120, wHeight: 80, wRotation: 0}
];
const box = CM.boundsOf(members);
const minimum = {w: 100, h: 60};
function arrange(mode, width = 350, height = 210, items = members) {
    return JSON.parse(JSON.stringify(Fusion.arrange(items, Fusion.settings({mode, gap: 10}), box, width, height, minimum)));
}

assert.equal(Fusion.modes.length, 7);
assert.equal(Fusion.styles.length, 8);
assert.deepEqual(arrange('unified'), arrange('grid'));
const singleColumn = Fusion.settings({mode: 'grid', columns: 1});
assert.equal(Fusion.arrange(members, singleColumn, box, 350, 210, minimum)[1].x, box.x);
assert.ok(arrange('unified')[1].x > box.x);
assert.equal(arrange('seamless')[1].x, -25);
assert.equal(arrange('horizontal')[2].y, box.y);
assert.equal(arrange('vertical')[2].x, box.x);
assert.equal(arrange('adaptive')[2].y, box.y);
assert.equal(arrange('adaptive', 210)[2].y, 170);
assert.deepEqual(arrange('freeform', box.w * 2, box.h * 2)[1], {x: 60, y: 60, w: 160, h: 240});
assert.deepEqual(arrange('horizontal', 350, 210, [members[1], members[0]])[0], {x: -200, y: 60, w: 210, h: 170});
assert.deepEqual({...Fusion.fit({w: 150, h: 200}, {minW: 40, maxW: 300, minH: 20, maxH: 300, minA: 2, maxA: 3})}, {w: 150, h: 75});

const style = JSON.stringify(Fusion.settings({mode: 'freeform', style: 'custom', background: '#123456', animation: 'fade'}));
const fusion = members.map((widget, i) => ({...widget, wGroup: 'system', wFusion: style, wFusionIndex: i}));
assert.equal(Fusion.groups(fusion.slice(0, 2))[0].members.length, 2);
assert.equal(Fusion.groups(fusion)[0].options.background, '#123456');
assert.equal(Fusion.groups(fusion.map(w => ({...w, wFusion: ''}))).length, 0);
assert.equal(Fusion.groups(fusion.map(w => ({...w, wGroup: ''}))).length, 0);
assert.deepEqual(Array.from(CM.expandSelection(fusion, ['a'])), ['a', 'b', 'c']);

const moved = fusion.map(w => ({...w, wX: w.wX + 50, wY: w.wY - 200}));
const saved = JSON.parse(JSON.stringify(Fusion.forStorage(moved.map(w => ({...w})))));
assert.deepEqual(saved[1].wFusionPosition, [-150, -140, 130, 0]);
assert.deepEqual(saved.map(w => Fusion.restorePosition({...w, wX: 0, wY: 0})), moved);
assert.equal(Fusion.restorePosition({...moved[0], wFusionPosition: [0, 0, '10', 0]}).wX, moved[0].wX);
const preset = CM.makeComposition('Dashboard', moved, {});
const first = Fusion.groups(CM.instantiateComposition(preset, 140, -400, 0))[0];
const second = Fusion.groups(CM.instantiateComposition(preset, 900, 300, 0))[0];
assert.notEqual(first.id, second.id);
assert.equal(first.options.animation, 'fade');
assert.deepEqual(Array.from(first.members, w => w.wX - first.box.x), [0, 130, 0]);
assert.equal(first.box.y + first.box.h / 2, -400);
assert.equal(second.box.y + second.box.h / 2, 300);
assert.equal(Fusion.settings('{broken'), null);
console.log('PASS: seven Fusion layouts, resize and rotation, grouping, move, relative save and composition restore');
