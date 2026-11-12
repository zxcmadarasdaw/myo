.pragma library

// Pure policy: never changes theme, layout, wallpaper or animation preferences.
function normalizeProfile(value) {
    return ["Performance", "Balanced", "Ultra"].indexOf(value) >= 0 ? value : "Balanced";
}

function policy(profile, safeMode, backends, shaderErrors) {
    profile = normalizeProfile(profile);
    const names = Object.keys(backends || {}).map(function(k) { return backends[k]; });
    const fallback = !!safeMode || names.indexOf("Software") >= 0 || names.indexOf("Null") >= 0 || Object.keys(shaderErrors || {}).length > 0;
    const effective = fallback ? "Performance" : profile;
    return {
        profile: effective, fallback: fallback, shaders: !fallback,
        blur: !fallback && effective !== "Performance",
        textureScale: effective === "Ultra" ? 1 : (effective === "Balanced" ? 0.65 : 0.35),
        blurScale: effective === "Ultra" ? 1 : (effective === "Balanced" ? 0.65 : 0),
        spectrumFps: effective === "Ultra" ? 60 : (effective === "Balanced" ? 30 : 20),
        wallpaperTransitions: !fallback && effective !== "Performance"
    };
}

function recommendation(report, state, backends, shaderStates) {
    if (state.fallback) return {profile: "Performance", reason: "Safe fallback is active. Resolve renderer/shader errors before restoring effects."};
    if (!report || report.status !== "ok" || !report.gpus || !report.gpus.length)
        return {profile: "Balanced", reason: "GPU probes are incomplete. Balanced is the conservative starting point."};
    if ((report.issues || []).some(function(i) { return i.severity === "warning"; }))
        return {profile: "Performance", reason: "Resolve the driver/session/access warnings before increasing quality."};
    const known = Object.keys(backends || {}).some(function(k) { return backends[k] !== "Unknown"; });
    const compiled = Object.keys(shaderStates || {}).some(function(k) { return shaderStates[k] === "compiled"; });
    return {profile: "Balanced", reason: known && compiled
        ? "A graphics backend and a compiled shader were observed. Start with Balanced; try Ultra while checking frame pacing on your monitors. No FPS benchmark has been run."
        : "Driver inventory is available; renderer/shader checks are still incomplete. Keep Balanced and open the shader preview."};
}

function hardwareChanged(previous, current) {
    return !!(previous && current && previous !== current);
}

if (typeof module !== "undefined") module.exports = {normalizeProfile: normalizeProfile, policy: policy, recommendation: recommendation, hardwareChanged: hardwareChanged};
