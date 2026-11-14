.pragma library

// Atelier looks shared by every widget type. A face never copies this table: it asks
// AtelierKit for the tokens of its `faceStyle` and AtelierCard draws the frame, so a new
// look is one more entry here (plus a label) and works on every Atelier face at once.
//
//   frame:   plain | sheen | window | rule | brackets | scrim
//   header:  label | dot | titlebar | serif | kicker | code | none
//   display / label: sans | serif | mono   (font families, see AtelierKit)
//   meter:   line | hair | pill | blocks | ticks | bar
//   radius, pad: scaled by AtelierKit; fill: opacity of the surface (0 = none)
var IDS = ["matte", "premium", "minimal", "retro", "elegant", "editorial", "technical", "borderless", "compact"];

var STYLES = {
    matte: {
        frame: "plain", header: "label", display: "sans", label: "sans",
        radius: 12, fill: 0.86, fillTone: "base", border: 0.1, accentBorder: false,
        displayWeight: 300, caps: true, tracking: 1.4, pad: 1.0, meter: "line", spark: true
    },
    premium: {
        frame: "sheen", header: "dot", display: "sans", label: "sans",
        radius: 16, fill: 0.93, fillTone: "gradient", border: 0.2, accentBorder: true,
        displayWeight: 200, caps: false, tracking: 0.3, pad: 1.15, meter: "pill", spark: true
    },
    minimal: {
        frame: "plain", header: "label", display: "sans", label: "sans",
        radius: 4, fill: 0.55, fillTone: "base", border: 0.12, accentBorder: false,
        displayWeight: 300, caps: true, tracking: 1.6, pad: 0.9, meter: "hair", spark: false
    },
    retro: {
        frame: "window", header: "titlebar", display: "mono", label: "mono",
        radius: 2, fill: 0.95, fillTone: "crust", border: 0.6, accentBorder: true,
        displayWeight: 500, caps: true, tracking: 1.0, pad: 0.85, meter: "blocks", spark: true
    },
    elegant: {
        frame: "plain", header: "serif", display: "serif", label: "serif",
        radius: 20, fill: 0.8, fillTone: "base", border: 0.08, accentBorder: false,
        displayWeight: 300, caps: false, tracking: 0.2, pad: 1.25, meter: "hair", spark: false
    },
    editorial: {
        frame: "rule", header: "kicker", display: "serif", label: "sans",
        radius: 0, fill: 0.34, fillTone: "crust", border: 0, accentBorder: false,
        displayWeight: 600, caps: true, tracking: 3.0, pad: 0.75, meter: "bar", spark: false
    },
    technical: {
        frame: "brackets", header: "code", display: "mono", label: "mono",
        radius: 3, fill: 0.9, fillTone: "crust", border: 0.16, accentBorder: false,
        displayWeight: 400, caps: true, tracking: 0.8, pad: 0.9, meter: "ticks", spark: true
    },
    borderless: {
        frame: "scrim", header: "none", display: "sans", label: "sans",
        radius: 0, fill: 0.0, fillTone: "base", border: 0, accentBorder: false,
        displayWeight: 200, caps: true, tracking: 2.0, pad: 0.6, meter: "hair", spark: false
    },
    compact: {
        frame: "plain", header: "none", display: "sans", label: "sans",
        radius: 8, fill: 0.9, fillTone: "base", border: 0.1, accentBorder: false,
        displayWeight: 400, caps: true, tracking: 1.0, pad: 0.65, meter: "line", spark: false
    }
};

var LABELS = {
    matte: "Matte", premium: "Premium Dark", minimal: "Minimal", retro: "Retro", elegant: "Elegant",
    editorial: "Editorial", technical: "Technical", borderless: "Borderless", compact: "Compact"
};

function get(id) {
    return STYLES[id] || STYLES.matte;
}

function valid(id) {
    return STYLES.hasOwnProperty(id);
}
