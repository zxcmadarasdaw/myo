.pragma library

// File Dock: icon glyph (Nerd Font) and accent for a path.

var imageExt = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "avif", "tif", "tiff", "ico"];

var groups = [
    { ext: ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "avif", "tif", "tiff", "ico", "heic"], icon: "\u{F021F}", tone: "green" },
    { ext: ["mp4", "mkv", "webm", "avi", "mov", "flv", "wmv", "m4v"], icon: "\u{F0381}", tone: "red" },
    { ext: ["mp3", "flac", "ogg", "wav", "m4a", "opus", "aac"], icon: "\u{F0388}", tone: "peach" },
    { ext: ["pdf"], icon: "\u{F0226}", tone: "red" },
    { ext: ["zip", "tar", "gz", "xz", "zst", "bz2", "7z", "rar", "rpm", "deb"], icon: "\u{F05C4}", tone: "yellow" },
    { ext: ["doc", "docx", "odt", "rtf"], icon: "\u{F022C}", tone: "blue" },
    { ext: ["xls", "xlsx", "ods", "csv"], icon: "\u{F021B}", tone: "green" },
    { ext: ["ppt", "pptx", "odp"], icon: "\u{F0227}", tone: "peach" },
    { ext: ["txt", "md", "log", "org", "rst"], icon: "\u{F0219}", tone: "text" },
    { ext: ["sh", "bash", "zsh", "fish", "py", "js", "ts", "qml", "c", "cpp", "h", "rs", "go", "java", "lua", "json", "toml", "yaml", "yml", "html", "css"], icon: "\u{F0169}", tone: "mauve" },
    { ext: ["iso", "img", "qcow2"], icon: "\u{F02CA}", tone: "subtext1" },
    { ext: ["desktop", "appimage", "flatpakref"], icon: "\u{F08C6}", tone: "teal" }
];

function extOf(path) {
    var name = baseName(path);
    var dot = name.lastIndexOf(".");
    return dot > 0 ? name.substring(dot + 1).toLowerCase() : "";
}

function baseName(path) {
    var p = String(path || "").replace(/\/+$/, "");
    if (p === "") return "/";
    return p.substring(p.lastIndexOf("/") + 1);
}

function isImage(path) {
    return imageExt.indexOf(extOf(path)) !== -1;
}

function folderIcon(path, home) {
    var p = String(path || "").replace(/\/+$/, "");
    if (p === String(home || "").replace(/\/+$/, "")) return "\u{F10B5}";
    var n = baseName(p).toLowerCase();
    if (n === "downloads" || n === "загрузки") return "\u{F024D}";
    if (n === "documents" || n === "документы") return "\u{F0C82}";
    if (n === "pictures" || n === "изображения") return "\u{F024F}";
    if (n === "music" || n === "музыка") return "\u{F1359}";
    if (n === "videos" || n === "видео") return "\u{F1C29}";
    if (n === "desktop" || n === "рабочий стол") return "\u{F01C4}";
    return "\u{F024B}";
}

function icon(path, isDir, home) {
    if (isDir) return folderIcon(path, home);
    var e = extOf(path);
    for (var i = 0; i < groups.length; i++) if (groups[i].ext.indexOf(e) !== -1) return groups[i].icon;
    return "\u{F0214}";
}

function tone(path, isDir) {
    if (isDir) return "blue";
    var e = extOf(path);
    for (var i = 0; i < groups.length; i++) if (groups[i].ext.indexOf(e) !== -1) return groups[i].tone;
    return "subtext1";
}

// "file:///home/a/My%20File.txt" -> "/home/a/My File.txt"
function urlToPath(url) {
    var s = String(url || "");
    if (s.indexOf("file://") === 0) s = s.substring(7);
    try { s = decodeURIComponent(s); } catch (e) {}
    return s;
}

// Parse the saved list; tolerate garbage, drop duplicates.
function parse(json) {
    var out = [];
    var seen = {};
    var arr;
    try { arr = JSON.parse(json || "[]"); } catch (e) { arr = []; }
    if (!Array.isArray(arr)) return out;
    for (var i = 0; i < arr.length; i++) {
        var it = arr[i];
        if (!it || typeof it.path !== "string" || it.path === "" || seen[it.path]) continue;
        seen[it.path] = true;
        out.push({ path: it.path, name: typeof it.name === "string" && it.name !== "" ? it.name : baseName(it.path), dir: !!it.dir });
    }
    return out;
}
