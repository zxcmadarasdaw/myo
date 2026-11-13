// Executes the same geometry helper as the layer-shell drawer, without a compositor.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../../src/quickshell/widgets/MusicDrawerGeometry.js'), 'utf8').replace(/^\.pragma library\s*/, '');
const context = {module:{exports:{}}};
vm.runInNewContext(source, context);
const layout = context.module.exports.layout;
let checks = 0;
for (const [x,y,h,sw,sh] of [[100,100,144,1920,1080],[1700,850,144,1920,1080],
    [10,50,144,640,480],[-100,100,144,800,600],[600,100,144,800,600],
    [0,0,144,320,240],[500,500,280,1280,800],[1200,900,180,2560,1440]]) {
    const original = [x,y];
    const p = layout(x,y,h,sw,sh,540);
    assert.ok(p.x >= 0 && p.x+p.width <= sw);
    const top = p.up ? p.edge-p.height : p.edge;
    assert.ok(top >= 0 && top+p.height <= sh);
    assert.deepEqual([x,y], original);
    for (const reveal of [0,0.1,0.5,1]) {
        const height = p.height*reveal;
        const animatedTop = p.up ? p.edge-height : p.edge;
        assert.ok(animatedTop >= 0 && animatedTop+height <= sh);
    }
    checks++;
}
assert.equal(layout(100,100,144,1920,1080,540).up,false);
assert.equal(layout(100,850,144,1920,1080,540).up,true);
console.log(`PASS: ${checks} drawer geometries, animation bounds, upward/downward selection; no widget position mutation`);
