.pragma library
.import "CanvasMath.js" as CM

var modes = ["unified", "seamless", "grid", "horizontal", "vertical", "freeform", "adaptive"];
var styles = ["matte", "minimal", "editorial", "retro", "technical", "borderless", "compact", "custom"];

function number(value, fallback, min, max) {
    return typeof value === "number" && isFinite(value) ? Math.max(min, Math.min(max, value)) : fallback;
}

function settings(data) {
    if (typeof data === "string") {
        try { data = JSON.parse(data); } catch (_) { data = null; }
    }
    if (!data || typeof data !== "object") return null;
    return {
        mode: modes.includes(data.mode) ? data.mode : "unified",
        style: styles.includes(data.style) ? data.style : "matte",
        gap: number(data.gap, 12, 0, 128),
        padding: number(data.padding, 14, 0, 128),
        columns: Math.round(number(data.columns, 2, 1, 12)),
        opacity: number(data.opacity, 0.92, 0, 1),
        radius: number(data.radius, 16, 0, 60),
        dividers: data.dividers === true,
        animation: data.animation === "fade" ? "fade" : "none",
        background: /^#[0-9a-fA-F]{6}$/.test(data.background || "") ? data.background : "",
        title: typeof data.title === "string" ? data.title.trim().slice(0, 60) : ""
    };
}

function groups(records) {
    const sets = new Map();
    for (const record of records) {
        if (!record.wGroup || !record.wFusion) continue;
        const id = String(record.wGroup);
        if (!sets.has(id)) sets.set(id, []);
        sets.get(id).push(record);
    }
    const result = [];
    sets.forEach((members, id) => {
        if (members.length < 2) return;
        members.sort((a, b) => (a.wFusionIndex || 0) - (b.wFusionIndex || 0));
        const options = settings(members[0].wFusion);
        const box = CM.boundsOf(members);
        if (!options || !box) return;
        result.push({id: id, box: box, options: options, members: members});
    });
    return result;
}

function forStorage(records) {
    for (const group of groups(records)) {
        const {x, y} = group.box;
        for (const member of group.members)
            member.wFusionPosition = [x, y, member.wX - x, member.wY - y];
    }
    return records;
}

function restorePosition(record) {
    if (!record || typeof record !== "object") return record;
    const position = record.wFusionPosition;
    if (record.wGroup && settings(record.wFusion) && Array.isArray(position) && position.length === 4
            && position.every(n => typeof n === "number" && isFinite(n))) {
        const x = position[0] + position[2];
        const y = position[1] + position[3];
        if (isFinite(x) && isFinite(y)) {
            record.wX = x;
            record.wY = y;
        }
    }
    delete record.wFusionPosition;
    return record;
}

function arrange(members, options, box, width, height, minimum) {
    const gap = options.mode === "seamless" ? 0 : options.gap;
    const count = members.length;
    let columns = Math.min(count, options.columns);
    switch (options.mode) {
    case "unified": columns = Math.ceil(Math.sqrt(count)); break;
    case "vertical": columns = 1; break;
    case "horizontal": columns = count; break;
    case "adaptive": columns = Math.max(1, Math.min(count, Math.floor((width + gap) / (minimum.w + gap)))); break;
    }
    if (options.mode === "freeform") {
        const sx = Math.max(width / box.w, ...members.map(member => minimum.w / CM.widgetBox(member).w));
        const sy = Math.max(height / box.h, ...members.map(member => minimum.h / CM.widgetBox(member).h));
        return members.map(member => ({
            x: box.x + (member.wX - box.x) * sx,
            y: box.y + (member.wY - box.y) * sy,
            w: member.wWidth * (member.wRotation % 180 ? sy : sx),
            h: member.wHeight * (member.wRotation % 180 ? sx : sy)
        }));
    }
    const rows = Math.ceil(count / columns);
    const w = Math.max(minimum.w, (width - gap * (columns - 1)) / columns);
    const h = Math.max(minimum.h, (height - gap * (rows - 1)) / rows);
    return members.map((member, i) => ({
        x: box.x + i % columns * (w + gap),
        y: box.y + Math.floor(i / columns) * (h + gap),
        w: member.wRotation % 180 ? h : w,
        h: member.wRotation % 180 ? w : h
    }));
}

function fit(rect, constraints) {
    if (!constraints) return {w: rect.w, h: rect.h};
    const c = constraints;
    let w = Math.max(c.minW, Math.min(c.maxW, rect.w));
    let h = Math.max(c.minH, Math.min(c.maxH, rect.h));
    if (c.minA > 0 && w < h * c.minA) h = Math.max(c.minH, w / c.minA);
    if (c.maxA > 0 && w > h * c.maxA) w = Math.max(c.minW, h * c.maxA);
    return {w: w, h: h};
}
