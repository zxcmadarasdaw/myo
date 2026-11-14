.pragma library

// One reading for the Restrained / Lush usage faces, from SysData values.
// Returns { value: 0..1, text, detail, title, titleKey, icon }.
function num(v) {
    var n = Number(v);
    return isNaN(n) ? 0 : n;
}

function clamp01(v) {
    return Math.max(0, Math.min(1, v));
}

function read(kind, cpu, ramPercent, ramGb, temp, diskPercent, diskGb, diskTotalGb) {
    switch (kind) {
    case "ram":
        return {
            value: clamp01(num(ramPercent) / 100),
            text: num(ramGb).toFixed(1) + "G",
            detail: Math.round(num(ramPercent)) + "%",
            title: "RAM", titleKey: "quickactions.systemusage.ram",
            icon: String.fromCodePoint(0xF035C)
        };
    case "temp":
        return {
            value: clamp01(num(temp) / 100),
            text: Math.round(num(temp)) + "°",
            detail: "",
            title: "Temp", titleKey: "quickactions.systemusage.temp",
            icon: String.fromCodePoint(0xF050F)
        };
    case "disk":
        return {
            value: clamp01(num(diskPercent) / 100),
            text: Math.round(num(diskPercent)) + "%",
            detail: num(diskTotalGb) > 0 ? num(diskGb).toFixed(0) + " / " + num(diskTotalGb).toFixed(0) + "G" : "",
            title: "Disk", titleKey: "quickactions.systemusage.disk",
            icon: String.fromCodePoint(0xF02CA)
        };
    default:
        return {
            value: clamp01(num(cpu) / 100),
            text: Math.round(num(cpu)) + "%",
            detail: "",
            title: "CPU", titleKey: "quickactions.systemusage.cpu",
            icon: String.fromCodePoint(0xF035B)
        };
    }
}
