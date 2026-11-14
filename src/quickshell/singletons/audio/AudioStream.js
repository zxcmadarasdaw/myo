.pragma library

function isSerpantinumStream(properties) {
    const appId = properties["application.id"] || "";
    const appName = properties["application.name"] || "";
    if (appId === "serpantinum-sfx" || appId === "serpantinum" || appId === "org.serpantinum.sfx") return true;
    if (appName === "serpantinum-sfx" || appName === "serpantinum") return true;
    if (properties["node.group"] === "serpantinum-audio" || properties["node.link-group"] === "serpantinum-audio") return true;
    const mediaFile = properties["media.filename"] || properties["media.name"] || "";
    return String(mediaFile).includes("assets/sounds/");
}
