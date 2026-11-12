pragma Singleton
import QtQuick
import Quickshell

QtObject {
    id: root

    // SERPANTINUM_DIR is exported by serpantinumd. When the shell is started some
    // other way (plain `quickshell -p .../Shell.qml`, a test copy, a wrapper) the
    // variable is missing; resolve the install tree from this file's location
    // instead of the process working directory. This file lives in
    // <src>/quickshell/singletons/system/.
    readonly property string serpantinumDir: {
        const fromEnv = Quickshell.env("SERPANTINUM_DIR");
        if (fromEnv) return String(fromEnv).replace(/\/+$/, "");
        const here = decodeURIComponent(String(Qt.resolvedUrl("../../../")).replace(/^file:\/\//, ""));
        return here.replace(/\/+$/, "");
    }

    // Converts an absolute filesystem path to a file:// URL that QML loaders
    // accept. Characters such as '#', '?' and '%' are legal in file names but
    // would otherwise be parsed as URL fragment/query/escape and break loading.
    function fileUrl(path) {
        if (path === undefined || path === null) return "";
        let p = String(path).trim();
        if (p === "") return "";
        if (p.startsWith("file://")) return p;
        if (!p.startsWith("/")) return "";
        return "file://" + p.split("/").map(part => encodeURIComponent(part)).join("/");
    }
    readonly property string qsDir: Quickshell.env("QS_DIR")

    readonly property string home: Quickshell.env("HOME")
    readonly property string xdgRuntimeDir: Quickshell.env("XDG_RUNTIME_DIR")

    readonly property string cacheDir: Quickshell.env("QS_CACHE_DIR") ? Quickshell.env("QS_CACHE_DIR") : (home + "/.cache/serpantinum")
    readonly property string stateDir: Quickshell.env("QS_STATE_DIR") ? Quickshell.env("QS_STATE_DIR") : (home + "/.local/state/serpantinum")
    readonly property string runDir: Quickshell.env("QS_RUN_DIR") ? Quickshell.env("QS_RUN_DIR") : ((xdgRuntimeDir !== "" ? xdgRuntimeDir : "/tmp") + "/serpantinum")
    readonly property string logDir: Quickshell.env("QS_LOG_DIR") ? Quickshell.env("QS_LOG_DIR") : (runDir + "/logs")

    function getCacheDir(widgetName) {
        if (!widgetName || widgetName === "serpantinum" || cacheDir.endsWith("/" + widgetName)) {
            Quickshell.execDetached(["mkdir", "-p", cacheDir]);
            return cacheDir;
        }
        var envPath = Quickshell.env("QS_CACHE_" + widgetName.toUpperCase());
        var finalPath = envPath ? envPath : (cacheDir + "/" + widgetName);
        Quickshell.execDetached(["mkdir", "-p", finalPath]);
        return finalPath;
    }

    function getStateDir(widgetName) {
        if (!widgetName || widgetName === "serpantinum" || stateDir.endsWith("/" + widgetName)) {
            Quickshell.execDetached(["mkdir", "-p", stateDir]);
            return stateDir;
        }
        var envPath = Quickshell.env("QS_STATE_" + widgetName.toUpperCase());
        var finalPath = envPath ? envPath : (stateDir + "/" + widgetName);
        Quickshell.execDetached(["mkdir", "-p", finalPath]);
        return finalPath;
    }

    function getRunDir(widgetName) {
        if (!widgetName || widgetName === "serpantinum" || runDir.endsWith("/" + widgetName)) {
            Quickshell.execDetached(["mkdir", "-p", runDir]);
            return runDir;
        }
        var envPath = Quickshell.env("QS_RUN_" + widgetName.toUpperCase());
        var finalPath = envPath ? envPath : (runDir + "/" + widgetName);
        Quickshell.execDetached(["mkdir", "-p", finalPath]);
        return finalPath;
    }

    function getLogDir(widgetName) {
        if (!widgetName || widgetName === "serpantinum" || logDir.endsWith("/" + widgetName)) {
            Quickshell.execDetached(["mkdir", "-p", logDir]);
            return logDir;
        }
        var envPath = Quickshell.env("QS_LOG_" + widgetName.toUpperCase());
        var finalPath = envPath ? envPath : (logDir + "/" + widgetName);
        Quickshell.execDetached(["mkdir", "-p", finalPath]);
        return finalPath;
    }
}
