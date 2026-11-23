// Tests the shipped transition policy and note preview helper without a compositor.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const repo = path.resolve(__dirname, "../..");
const read = file => fs.readFileSync(path.join(repo, file), "utf8");

const wallpaper = read("src/quickshell/singletons/theme/Wallpaper.qml");
const ids = JSON.parse(wallpaper.match(/transitionIds: (\[[^\n]+\])/)[1]);
const state = { transitionIds: ids, transitionModes: ["random", "custom"], swipeDirections: ["left", "right"] };
state.defaultTransitionSettings = vm.runInNewContext("(" + wallpaper.match(/defaultTransitionSettings: \((\{[\s\S]*?\})\)/)[1] + ")",
    { root: state });

const profiles = {
    wallpaperTransition: { mode: "custom", pool: ["blinds"] },
    wallpaperTransitionByWorkspace: {
        "hyprland:DP-1:3": { mode: "custom", pool: ["hex"], effects: { hex: {size: 120, duration: 2400, speed: 2} } },
        "hyprland:DP-2:6": { mode: "custom", pool: ["ink"], effects: { ink: {origin: "center"} } }
    }
};
const focused = { id: 3, monitor: {name: "DP-1"} };
const context = {
    root: state,
    Config: { getSetting: (key, fallback) => profiles[key] ?? fallback },
    Compositor: { name: "hyprland" },
    Hyprland: { focusedWorkspace: focused, monitors: { values: [
        { name: "DP-1", activeWorkspace: focused }, { name: "DP-2", activeWorkspace: {id: 6} }
    ] } },
    NiriState: { workspacesMap: { 12: {output: "DP-1", idx: 2, is_active: true, is_focused: true} } },
    UmbrielState: { focusedOutput: "DP-1", activeIndicesByOutput: {"DP-1": 3} }
};
vm.createContext(context);
for (const name of ["transitionWorkspace", "transitionSettings", "transitionDuration", "hexCells", "resolveTransition"]) {
    const start = wallpaper.indexOf("function " + name + "(");
    const end = wallpaper.indexOf("\n    }", start);
    const source = wallpaper.slice(start, end + 6).replace(/(\([^\n]*\)):\s*\w+\s*\{/, "$1 {")
        .replace(/(\w+): (?:string|int|var)(?=[,)= ])/g, "$1");
    state[name] = vm.runInContext("(" + source + ")", context);
}
assert.deepEqual(ids, ["fade", "wipe", "circle", "swipe", "paint", "wave", "blinds", "clock", "hex", "ink"]);
assert.equal(state.transitionWorkspace(""), "hyprland:DP-1:3");
assert.equal(state.resolveTransition(-1, "DP-1").duration, 1200);
assert.equal(state.resolveTransition(-1, "DP-1").hexSize, 120);
assert.equal(state.resolveTransition(-1, "DP-2").type, ids.indexOf("ink"));
assert.equal(state.resolveTransition(-1, "DP-2").centered, true);
assert.equal(state.resolveTransition(-1, "DP-3").type, ids.indexOf("blinds"));
context.Compositor.name = "niri";
assert.equal(state.transitionWorkspace("DP-1"), "niri:DP-1:2");
context.Compositor.name = "umbriel";
assert.equal(state.transitionWorkspace(""), "umbriel:DP-1:4");
assert.equal(state.hexCells({size: 400}), 240);

const tab = read("src/quickshell/guide/wallpaper/WallpaperTabState.qml");
context.Wallpaper = state;
context.Config.setSetting = (key, value) => { profiles[key] = value; };
context.wallpaperTabRoot = { transitionWorkspace: "hyprland:DP-1:3" };
for (const name of ["saveTransition", "resetTransitionWorkspace"]) {
    const start = tab.indexOf("function " + name + "(");
    const end = tab.indexOf("\n    }", start);
    context[name] = vm.runInContext("(" + tab.slice(start, end + 6) + ")", context);
}
context.saveTransition({mode: "custom", pool: ["clock"]});
assert.equal(profiles.wallpaperTransitionByWorkspace["hyprland:DP-1:3"].pool[0], "clock");
assert.equal(profiles.wallpaperTransitionByWorkspace["hyprland:DP-2:6"].pool[0], "ink");
context.resetTransitionWorkspace();
assert.equal(profiles.wallpaperTransitionByWorkspace["hyprland:DP-1:3"], undefined);
assert.equal(context.wallpaperTabRoot.transition.pool[0], "blinds");

const notes = vm.runInNewContext(read("src/quickshell/quickactions/actions/NotesFormat.js").replace(".pragma library", "") +
    "\nlistSnippet");
assert.equal(notes(" \n"), "...");
assert.equal(notes("\n Hello\nworld "), "Hello world");
assert.equal(notes("x".repeat(300)).length, 241);
assert.match(read("src/quickshell/quickactions/actions/Notes.qml"), /active: root\.isEditing/);
console.log("PASS: transition profiles, independent monitors, duration, cells and bounded notes preview");
