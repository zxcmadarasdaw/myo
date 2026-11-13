import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell.Io
import "../"

// Settings -> Diagnostics. Data comes from scripts/system/serp_diag.py; the
// diagnostic archive is written locally and never uploaded.
GuideTab {
    id: tab
    function tr(en, ru) { return I18n.currentLang === "ru" ? ru : en; }
    readonly property string script: Caching.serpantinumDir + "/scripts/system/serp_diag.py"
    property var d: null
    property bool loading: false
    property string exportResult: ""
    property bool exportOk: false

    function refresh() {
        loading = true;
        summaryProc.running = false;
        summaryProc.running = true;
    }
    function doExport() {
        let cmd = ["python3", script, "export"];
        if (!redHome.checked) cmd.push("--keep-home");
        if (!redUser.checked) cmd.push("--keep-user");
        if (!redTokens.checked) cmd.push("--keep-tokens");
        if (!inclSettings.checked) cmd.push("--no-settings");
        if (inclDumps.checked) cmd.push("--include-dumps");
        exportProc.command = cmd;
        exportResult = tr("Creating archive…", "Создание архива…");
        exportOk = false;
        exportProc.running = true;
    }

    Process {
        id: summaryProc
        command: ["python3", tab.script, "summary"]
        stdout: StdioCollector {
            onStreamFinished: {
                tab.loading = false;
                try { tab.d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { tab.d = { ok: false, error: String(e) }; }
            }
        }
        onExited: (code) => { tab.loading = false; }
    }
    Process {
        id: exportProc
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null;
                try { r = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { r = { ok: false, error: String(e) }; }
                tab.exportOk = !!r.ok;
                tab.exportResult = r.ok ? tab.tr("Saved: ", "Сохранено: ") + r.path + "\n" + tab.tr("Contains: ", "Содержит: ") + (r.included || []).join(", ")
                                        : tab.tr("Export failed: ", "Ошибка экспорта: ") + r.error;
            }
        }
    }

    onVisibleChanged: if (visible && d === null && !loading) refresh()
    Component.onCompleted: if (visible) refresh()

    component Info: Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        color: ThemeBackend.text
        font.family: ThemeBackend.fontFamily
        font.pixelSize: tab.rootObj.s(12)
    }
    component Heading: Info {
        font.pixelSize: tab.rootObj.s(16)
        font.bold: true
        Layout.topMargin: tab.rootObj.s(10)
    }
    component Action: Controls.Button {
        font.family: ThemeBackend.fontFamily
        palette.button: ThemeBackend.surface1
        palette.buttonText: ThemeBackend.text
    }
    component Check: Controls.CheckBox {
        font.family: ThemeBackend.fontFamily
        palette.windowText: ThemeBackend.text
        palette.text: ThemeBackend.text
        palette.base: ThemeBackend.surface0
    }
    component Mono: Rectangle {
        id: mono
        property string text: ""
        Layout.fillWidth: true
        implicitHeight: monoText.implicitHeight + tab.rootObj.s(12)
        radius: tab.rootObj.s(6)
        color: Qt.alpha(ThemeBackend.surface0, 0.6)
        Text {
            id: monoText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: tab.rootObj.s(6)
            text: mono.text
            wrapMode: Text.WrapAnywhere
            textFormat: Text.PlainText
            color: ThemeBackend.subtext1
            font.family: "monospace"
            font.pixelSize: tab.rootObj.s(11)
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: tab.rootObj.s(12)
        contentWidth: width
        contentHeight: body.implicitHeight + tab.rootObj.s(16)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Controls.ScrollBar.vertical: Controls.ScrollBar {}

        ColumnLayout {
            id: body
            width: parent.width - tab.rootObj.s(14)
            spacing: tab.rootObj.s(8)

            Heading { text: tab.tr("Diagnostics", "Диагностика"); font.pixelSize: tab.rootObj.s(18); Layout.topMargin: 0 }
            Info { color: ThemeBackend.subtext0; text: tab.tr("Local checks only. Nothing is sent to the internet.", "Только локальные проверки. Ничего не отправляется в интернет.") }
            RowLayout {
                Action { text: tab.loading ? tab.tr("Checking…", "Проверка…") : tab.tr("Refresh", "Обновить"); enabled: !tab.loading; onClicked: tab.refresh() }
                Controls.BusyIndicator { running: tab.loading; visible: tab.loading; implicitHeight: tab.rootObj.s(28); implicitWidth: implicitHeight }
            }
            Info { visible: tab.d !== null && !tab.d.ok; color: ThemeBackend.red; text: tab.d && tab.d.error ? tab.d.error : "" }

            Heading { text: tab.tr("Versions", "Версии") }
            Mono {
                text: !tab.d || !tab.d.ok ? "…" :
                    "Serpantinum " + (tab.d.serpantinum || "?") + "\n" +
                    "Quickshell: " + tab.d.quickshell + "\n" +
                    "Qt: " + tab.d.qt + (tab.d.qtSource ? "  (" + tab.d.qtSource + ")" : "") + "\n" +
                    "Hyprland: " + tab.d.hyprland + "\n" +
                    "OS: " + tab.d.os + (tab.d.liveSession ? "  [Live session]" : "") + "\n" +
                    "Wayland: " + (tab.d.session.wayland || "-") + "  Desktop: " + (tab.d.session.desktop || "-")
            }

            Heading { text: "Wallpaper Engine" }
            Info {
                text: !tab.d || !tab.d.ok ? "…" : (tab.d.wallpaperEngine.ipc === true ? "✓ " : tab.d.wallpaperEngine.ipc === false ? "✗ " : "? ") + tab.d.wallpaperEngine.detail
                color: tab.d && tab.d.ok && tab.d.wallpaperEngine.ipc === false ? ThemeBackend.peach : ThemeBackend.text
            }

            Heading { text: tab.tr("Core modules", "Основные модули") }
            Repeater {
                model: tab.d && tab.d.ok ? tab.d.modules : []
                delegate: Info {
                    required property var modelData
                    color: modelData.ok ? ThemeBackend.text : ThemeBackend.red
                    text: (modelData.ok ? "✓ " : "✗ ") + modelData.name + " — " + modelData.detail
                }
            }

            Heading { text: tab.tr("Dependencies", "Зависимости") }
            Repeater {
                model: tab.d && tab.d.ok ? tab.d.dependencies : []
                delegate: Info {
                    required property var modelData
                    color: modelData.ok === false ? (modelData.required ? ThemeBackend.red : ThemeBackend.peach) : ThemeBackend.text
                    text: (modelData.ok === true ? "✓ " : modelData.ok === false ? "✗ " : "? ") + modelData.name + " — " + modelData.purpose
                          + (modelData.ok === false ? (modelData.required ? tab.tr(" (required)", " (обязательно)") : tab.tr(" (optional)", " (необязательно)")) : "")
                          + (modelData.ok === null ? tab.tr(" (cannot check on this system)", " (на этой системе проверить нельзя)") : "")
                }
            }

            Heading { text: tab.tr("Recent crashes", "Последние аварийные завершения") }
            Info {
                visible: !!(tab.d && tab.d.ok && tab.d.crashes.length === 0)
                color: ThemeBackend.subtext0
                text: tab.tr("No Quickshell crash reports in ", "Нет отчётов о сбоях Quickshell в ") + (tab.d && tab.d.ok ? tab.d.crashDir : "") + tab.tr(". On a Live system they are lost after reboot.", ". В Live-системе они теряются после перезагрузки.")
            }
            Repeater {
                model: tab.d && tab.d.ok ? tab.d.crashes : []
                delegate: Mono {
                    required property var modelData
                    text: modelData.time + "  " + modelData.dir + "\n" + modelData.files.map(f => f.name + " (" + Math.round(f.size / 1024) + " KB)").join(", ") + (modelData.info ? "\n" + modelData.info : "")
                }
            }

            Heading { text: tab.tr("Recent shell errors", "Последние ошибки оболочки") }
            Info { visible: !!(tab.d && tab.d.ok && !tab.d.shellLogFound); color: ThemeBackend.subtext0; text: tab.tr("Shell log not found: ", "Журнал оболочки не найден: ") + (tab.d && tab.d.ok ? tab.d.shellLog : "") }
            Info { visible: !!(tab.d && tab.d.ok && tab.d.shellLogFound && tab.d.shellErrors.length === 0); color: ThemeBackend.green; text: tab.tr("No errors or warnings in the recent shell log.", "В последнем журнале оболочки нет ошибок и предупреждений.") }
            Mono { visible: !!(tab.d && tab.d.ok && tab.d.shellErrors.length > 0); text: tab.d && tab.d.ok ? tab.d.shellErrors.slice(-40).join("\n") : "" }

            Heading { text: tab.tr("Screen recording", "Запись экрана") }
            Check {
                text: tab.tr("Lighten the wallpaper while a screen recorder runs (OBS, wf-recorder, gpu-screen-recorder, wl-screenrec, Kooha)",
                             "Облегчать обои, пока работает запись экрана (OBS, wf-recorder, gpu-screen-recorder, wl-screenrec, Kooha)")
                checked: !!Config.getSetting("general.recordingLite", false)
                onToggled: Config.setSetting("general.recordingLite", checked)
            }
            Info {
                color: ThemeBackend.subtext0
                text: tab.tr("Off by default. When on, and only while recording, video wallpapers show a still frame, GIFs pause and wallpaper transitions are instant; everything returns automatically afterwards. Widgets, weather and music animations are not changed. Status now: ",
                             "По умолчанию выключено. Если включено, то только во время записи видеообои показывают неподвижный кадр, GIF на паузе, а переходы обоев мгновенные; после записи всё возвращается автоматически. Виджеты, погода и музыкальные анимации не меняются. Сейчас: ")
                    + (Wallpaper.captureLite ? tab.tr("recording detected, light mode active", "обнаружена запись, облегчённый режим активен")
                                             : Wallpaper.recordingLiteEnabled ? tab.tr("waiting for a recorder", "ожидание записи") : tab.tr("off", "выключено"))
            }

            Heading { text: "Export Diagnostic Report" }
            Info { color: ThemeBackend.subtext0; text: tab.tr("Creates a .tar.gz in your home folder with the summary above, the shell log, crash reports and (optionally) settings. Choose what to hide before exporting:", "Создаёт .tar.gz в домашней папке со сводкой выше, журналом оболочки, отчётами о сбоях и (по желанию) настройками. Выберите, что скрыть перед экспортом:") }
            Check { id: redHome; checked: true; text: tab.tr("Replace home folder paths with ~", "Заменить пути домашней папки на ~") }
            Check { id: redUser; checked: true; text: tab.tr("Hide user name and host name", "Скрыть имя пользователя и компьютера") }
            Check { id: redTokens; checked: true; text: tab.tr("Mask tokens, API keys and passwords", "Скрыть токены, API-ключи и пароли") }
            Check { id: inclSettings; checked: true; text: tab.tr("Include settings.json (location and profile removed)", "Включить settings.json (местоположение и профиль удаляются)") }
            Check { id: inclDumps; checked: false; text: tab.tr("Include raw crash dumps (may contain memory contents)", "Включить сырые дампы сбоев (могут содержать данные из памяти)") }
            Info { color: ThemeBackend.subtext0; text: tab.tr("Terminal and shell history and API-key files are never included.", "История терминала и оболочки и файлы API-ключей никогда не включаются.") }
            Action { text: "Export Diagnostic Report"; enabled: !exportProc.running; onClicked: tab.doExport() }
            Info { visible: tab.exportResult !== ""; color: tab.exportOk ? ThemeBackend.green : ThemeBackend.text; text: tab.exportResult }
        }
    }
}
