const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
function library(file) {
    const context = {module: {exports: {}}};
    vm.runInNewContext(fs.readFileSync(path.resolve(__dirname, '../../', file), 'utf8').replace(/^\.pragma library\s*/, ''), context);
    return context.module.exports;
}
const P = library('src/quickshell/singletons/system/GpuPolicy.js');
// Every custom QSB must participate in safe mode, including decorative shaders
// outside the main wallpaper/material components.
function qmlFiles(dir) {
    return fs.readdirSync(dir, {withFileTypes: true}).flatMap(e => e.isDirectory()
        ? qmlFiles(path.join(dir, e.name)) : (e.name.endsWith('.qml') ? [path.join(dir, e.name)] : []));
}
let guardedSources = 0;
for (const file of qmlFiles(path.resolve(__dirname, '../../src/quickshell'))) {
    for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
        if (line.includes('fragmentShader:')) {
            assert(line.includes('GpuCompatibility.shadersAllowed ?'), `Unguarded shader in ${file}`);
            guardedSources++;
        }
    }
}
assert(guardedSources >= 35);
const profiles = ['Performance', 'Balanced', 'Ultra'].map(p => P.policy(p, false, {screen: 'Vulkan'}, {}));
assert.equal(profiles[0].blur, false);
assert.equal(profiles[0].wallpaperTransitions, false);
assert(profiles[2].textureScale > profiles[1].textureScale);
assert(profiles[2].blurScale > profiles[1].blurScale);
assert(profiles[2].spectrumFps > profiles[1].spectrumFps);
assert.equal(P.normalizeProfile('corrupt-setting'), 'Balanced');
for (const backend of ['Software', 'Null']) {
    const p = P.policy('Ultra', false, {one: 'Vulkan', two: backend}, {});
    assert.equal(p.fallback, true);
    assert.equal(p.shaders, false);
}
assert.equal(P.policy('Ultra', true, {}, {}).shaders, false);
assert.equal(P.policy('Ultra', false, {}, {glass: 'failed'}).profile, 'Performance');
assert.equal(P.policy('Ultra', false, {}, {}).profile, 'Ultra'); // clearing errors restores chosen profile
assert.equal(P.hardwareChanged('amd', 'nvidia'), true);
assert.equal(P.hardwareChanged('amd', ''), false); // failed inventory is not a hardware removal
assert.equal(P.hardwareChanged('', 'amd'), false); // first run
const report = {status: 'ok', gpus: [{model: 'RTX 5060'}], issues: []};
const before = JSON.stringify(report);
assert.equal(P.recommendation(report, profiles[2], {screen: 'Vulkan'}, {preview: 'compiled'}).profile, 'Balanced');
assert.equal(JSON.stringify(report), before);
report.issues.push({severity: 'warning'});
assert.equal(P.recommendation(report, profiles[2], {}, {}).profile, 'Performance');
// Existing stage 1: spot-check coordinate preservation and zoom/resize invariants.
const C = library('src/quickshell/widgets/canvas/CanvasMath.js');
const cam = {x: -123, y: 67, zoom: 1.5};
const point = C.worldToScreen(cam, 43, -21);
const world = C.screenToWorld(cam, point.x, point.y);
assert.equal(world.x, 43); assert.equal(world.y, -21);
const zoomed = C.zoomAt(cam, 300, 200, 2, 0.1, 4);
const a = C.screenToWorld(cam, 300, 200), b = C.screenToWorld(zoomed, 300, 200);
assert(Math.abs(a.x - b.x) < 1e-8 && Math.abs(a.y - b.y) < 1e-8);
console.log(`PASS: ${guardedSources} guarded custom shaders; GPU profiles, fallback/recovery, multi-GPU, hardware identity, conservative recommendations; canvas coordinate/zoom smoke checks.`);
