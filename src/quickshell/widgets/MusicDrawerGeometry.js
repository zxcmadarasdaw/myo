.pragma library

function layout(x, y, widgetHeight, screenWidth, screenHeight, preferredHeight) {
    const width = Math.max(1, Math.min(570, screenWidth - 16));
    const below = Math.max(0, screenHeight - (y + widgetHeight) - 8);
    const above = Math.max(0, Math.min(screenHeight - 16, y - 8));
    const up = below < preferredHeight && above > below;
    const height = Math.max(0, Math.min(preferredHeight, up ? above : below));
    return { width: width, height: height, up: up,
        x: Math.max(8, Math.min(x, screenWidth - width - 8)),
        edge: up ? Math.min(screenHeight - 8, y) : Math.max(8, y + widgetHeight) };
}

if (typeof module !== "undefined") module.exports = {layout: layout};
