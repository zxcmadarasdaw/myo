import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as C
import Quickshell
import "../../"
import "../../../"

// Settings -> Search Wallpapers: internet search for images, GIFs and videos.
// This file is only the view. State, processes and downloads live in the
// WallpaperSearch singleton, so leaving the tab or closing the settings window
// keeps the results and lets a running download finish. Preview and Wallpaper
// Studio are loaded by URL: if QtMultimedia is missing only that overlay fails.
GuideTab {
    id: tab
    // Children with their own "tab" property bind to this (a plain "tab: tab" would bind to itself).
    readonly property Item tabRoot: tab

    function tr(en, ru) { return WallpaperSearch.tr(en, ru); }
    function s(v) { return rootObj ? rootObj.s(v) : v; }

    // Interface used by WallpaperStudio.qml and SearchPreview.qml.
    readonly property string script: WallpaperSearch.script
    readonly property string editedDir: WallpaperSearch.editedDir
    function fmtSize(b) { return WallpaperSearch.fmtSize(b); }
    function applyPath(path) { WallpaperSearch.applyPath(path, WallpaperSearch.monitor, WallpaperSearch.probed[path] || null); }
    function refreshLibrary() { WallpaperSearch.refreshLibrary(); }

    property string view: "search"           // search | library
    property bool showSettings: false
    property bool showDetails: false
    property var previewEntry: null
    property string studioPath: ""

    readonly property bool overlayOpen: previewEntry !== null || studioPath !== "" || showSettings
    readonly property int answered: Object.keys(WallpaperSearch.statusBySource).filter(k => !WallpaperSearch.statusBySource[k].skipped).length
    readonly property int askedCount: WallpaperSearch.plan.filter(p => !p.skipped).length
    readonly property var keyMissing: WallpaperSearch.plan.filter(p => p.skipCode === "key").map(p => p.source)

    onVisibleChanged: if (visible) activateTimer.restart()
    Component.onCompleted: if (visible) activateTimer.restart()
    Timer {
        id: activateTimer
        interval: 200
        onTriggered: {
            WallpaperSearch.refreshStatus();
            WallpaperSearch.loadHistory();
            WallpaperSearch.refreshLibrary();
            if (WallpaperSearch.pendingEdit !== "") { tab.studioPath = WallpaperSearch.pendingEdit; WallpaperSearch.pendingEdit = ""; }
            if (!tab.overlayOpen) searchField.forceActiveFocus();
        }
    }
    Connections {
        target: WallpaperSearch
        function onPendingEditChanged() {
            if (WallpaperSearch.pendingEdit !== "" && tab.visible) { tab.studioPath = WallpaperSearch.pendingEdit; WallpaperSearch.pendingEdit = ""; }
        }
        function onOfflineChanged() {
            if (WallpaperSearch.offline && WallpaperSearch.results.count === 0) tab.view = "library";
        }
    }

    // ---------------------------------------------------------------- building blocks
    component Txt: Text {
        color: ThemeBackend.text
        font.family: ThemeBackend.fontFamily
        font.pixelSize: tab.s(12)
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }
    component Icon: Text {
        color: ThemeBackend.text
        font.family: ThemeBackend.iconFont
        font.pixelSize: tab.s(15)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    component Btn: Rectangle {
        id: btn
        property string label: ""
        property string icon: ""
        property string hint: ""
        property color accent: Qt.alpha(ThemeBackend.surface1, 0.9)
        property color fg: ThemeBackend.text
        property bool active: true
        signal clicked()
        implicitHeight: tab.s(32)
        implicitWidth: btnRow.implicitWidth + tab.s(label !== "" ? 22 : 16)
        radius: tab.s(9)
        color: !active ? Qt.alpha(accent, 0.3) : (btnMa.pressed ? Qt.darker(accent, 1.18) : (btnMa.containsMouse ? Qt.lighter(accent, 1.15) : accent))
        opacity: active ? 1 : 0.5
        Behavior on color { ColorAnimation { duration: 110 } }
        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: tab.s(6)
            Icon { visible: btn.icon !== ""; text: btn.icon; color: btn.fg; font.pixelSize: tab.s(15); anchors.verticalCenter: parent.verticalCenter }
            Txt { visible: btn.label !== ""; text: btn.label; color: btn.fg; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.active) btn.clicked()
        }
        C.ToolTip.visible: hint !== "" && btnMa.containsMouse
        C.ToolTip.text: hint
        C.ToolTip.delay: 450
    }
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool on: false
        property color tint: ThemeBackend.mauve
        signal clicked()
        implicitHeight: tab.s(28)
        implicitWidth: chipText.implicitWidth + tab.s(22)
        radius: height / 2
        color: on ? Qt.alpha(tint, 0.22) : (chipMa.containsMouse ? Qt.alpha(ThemeBackend.text, 0.07) : "transparent")
        border.width: 1
        border.color: on ? Qt.alpha(tint, 0.85) : Qt.alpha(ThemeBackend.surface2, 0.55)
        Behavior on color { ColorAnimation { duration: 110 } }
        Txt { id: chipText; anchors.centerIn: parent; text: chip.label; color: chip.on ? chip.tint : ThemeBackend.subtext1; font.weight: Font.Medium }
        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }
    component Badge: Rectangle {
        id: badge
        property string label: ""
        property color tint: ThemeBackend.overlay1
        property bool solid: false
        implicitHeight: tab.s(19)
        implicitWidth: badgeText.implicitWidth + tab.s(10)
        radius: tab.s(6)
        color: solid ? Qt.alpha(ThemeBackend.crust, 0.78) : Qt.alpha(tint, 0.2)
        border.width: solid ? 0 : 1
        border.color: Qt.alpha(tint, 0.55)
        Text { id: badgeText; anchors.centerIn: parent; text: badge.label; color: badge.tint; font.family: ThemeBackend.fontFamily; font.pixelSize: tab.s(10); font.bold: true }
    }
    component GroupLabel: Txt {
        color: ThemeBackend.overlay2
        font.pixelSize: tab.s(11)
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        height: tab.s(28)
        verticalAlignment: Text.AlignVCenter
    }
    component Toggle: Rectangle {
        id: tg
        property bool on: false
        property string label: ""
        signal toggled()
        implicitHeight: tab.s(28)
        implicitWidth: tgRow.implicitWidth + tab.s(18)
        radius: height / 2
        color: tgMa.containsMouse ? Qt.alpha(ThemeBackend.text, 0.06) : "transparent"
        border.width: 1
        border.color: on ? Qt.alpha(ThemeBackend.green, 0.7) : Qt.alpha(ThemeBackend.surface2, 0.55)
        Row {
            id: tgRow
            anchors.centerIn: parent
            spacing: tab.s(8)
            Rectangle {
                width: tab.s(30); height: tab.s(16); radius: height / 2
                anchors.verticalCenter: parent.verticalCenter
                color: tg.on ? Qt.alpha(ThemeBackend.green, 0.85) : ThemeBackend.surface2
                Behavior on color { ColorAnimation { duration: 140 } }
                Rectangle {
                    width: tab.s(12); height: width; radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    x: tg.on ? parent.width - width - tab.s(2) : tab.s(2)
                    color: ThemeBackend.crust
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
            }
            Txt { text: tg.label; color: ThemeBackend.text; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: tgMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled() }
    }

    function statusTint(st) {
        if (!st) return ThemeBackend.overlay1;
        if (st.error) return ThemeBackend.red;
        if (st.skipped) return ThemeBackend.overlay1;
        return st.count > 0 ? ThemeBackend.green : ThemeBackend.yellow;
    }
    function statusText(st) {
        let name = WallpaperSearch.sourceLabel(st.source);
        if (st.error) return name + " · " + tr("error", "ошибка");
        if (st.skipped) return name + " · " + (st.skipCode === "key" ? tr("key needed", "нужен ключ") : tr("skipped", "пропущен"));
        let hidden = st.hidden ? Object.keys(st.hidden).reduce((a, k) => a + st.hidden[k], 0) : 0;
        return name + " · " + st.count + (hidden ? " (+" + hidden + tr(" hidden", " скрыто") + ")" : "");
    }
    function statusDetail(st) {
        let name = WallpaperSearch.sourceLabel(st.source);
        if (st.error) return name + ": " + st.error;
        if (st.skipped) return name + ": " + WallpaperSearch.skipText(st);
        let parts = [st.count + tr(" shown", " показано")];
        if (st.query && st.query !== WallpaperSearch.query) parts.push(tr("searched as “", "искали как «") + st.query + tr("”", "»"));
        let h = WallpaperSearch.hiddenText(st.hidden);
        if (h) parts.push(h);
        if (st.note) parts.push(st.note);
        parts.push(st.ms + " ms");
        return name + ": " + parts.join(" · ");
    }
    function openPreview(r) { previewEntry = r; }
    function openLocalPreview(it) {
        previewEntry = { local: true, path: it.path, kind: it.kind, format: it.format, title: it.title, id: it.path,
                         provenance: it.provenance, provenanceReason: it.provenanceReason, sourceName: it.source };
    }

    // ---------------------------------------------------------------- layout
    ColumnLayout {
        id: mainCol
        anchors.fill: parent
        anchors.margins: tab.s(14)
        spacing: tab.s(10)
        enabled: !tab.overlayOpen

        // header
        RowLayout {
            Layout.fillWidth: true
            spacing: tab.s(10)
            Rectangle {
                implicitWidth: tab.s(38); implicitHeight: tab.s(38); radius: tab.s(11)
                color: Qt.alpha(ThemeBackend.mauve, 0.18)
                Icon { anchors.centerIn: parent; text: "󰸉"; color: ThemeBackend.mauve; font.pixelSize: tab.s(19) }
            }
            ColumnLayout {
                spacing: 0
                Txt { text: tab.tr("Search Wallpapers", "Поиск обоев"); font.pixelSize: tab.s(18); font.weight: Font.Bold }
                Txt { text: tab.tr("Images, GIFs and videos from the internet — real results, real file data", "Изображения, GIF и видео из интернета — настоящие результаты и параметры файлов"); color: ThemeBackend.subtext0; font.pixelSize: tab.s(11) }
            }
            Item { Layout.fillWidth: true }
            Badge {
                visible: WallpaperSearch.onlineKnown
                label: WallpaperSearch.offline ? "OFFLINE" : "ONLINE"
                tint: WallpaperSearch.offline ? ThemeBackend.red : ThemeBackend.green
            }
            Row {
                spacing: tab.s(4)
                Chip { objectName: "viewSearch"; label: tab.tr("Search", "Поиск"); on: tab.view === "search"; onClicked: tab.view = "search" }
                Chip {
                    objectName: "viewLibrary"
                    label: tab.tr("Downloaded", "Скачанные") + (WallpaperSearch.library.length ? " · " + WallpaperSearch.library.length : "")
                    on: tab.view === "library"
                    onClicked: { tab.view = "library"; WallpaperSearch.refreshLibrary(); }
                }
            }
            Btn { objectName: "settingsButton"; icon: "󰒓"; hint: tab.tr("Sources, API keys and options", "Источники, API-ключи и настройки"); onClicked: tab.showSettings = true }
        }

        // search bar
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: tab.s(50)
            radius: tab.s(14)
            color: Qt.alpha(ThemeBackend.surface0, 0.75)
            border.width: 1
            border.color: searchField.activeFocus ? Qt.alpha(ThemeBackend.mauve, 0.9) : Qt.alpha(ThemeBackend.surface2, 0.5)
            Behavior on border.color { ColorAnimation { duration: 140 } }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: tab.s(16)
                anchors.rightMargin: tab.s(7)
                spacing: tab.s(10)
                Icon { text: WallpaperSearch.searching ? "󰔟" : "󰍉"; color: ThemeBackend.overlay2; font.pixelSize: tab.s(18) }
                C.TextField {
                    id: searchField
                    objectName: "searchField"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: WallpaperSearch.query
                    placeholderText: tab.tr("Search anything: “dark anime aesthetic”, “black hole 4k”, “ночной город”…",
                                            "Ищите что угодно: «dark anime aesthetic», «black hole 4k», «ночной город»…")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: tab.s(14)
                    color: ThemeBackend.text
                    placeholderTextColor: ThemeBackend.overlay1
                    selectByMouse: true
                    verticalAlignment: TextInput.AlignVCenter
                    background: Item {}
                    onAccepted: { WallpaperSearch.search(text); tab.view = "search"; }
                    Keys.onEscapePressed: (event) => { if (text !== "") { text = ""; event.accepted = true; } else event.accepted = false; }
                }
                Btn {
                    visible: searchField.text !== ""
                    icon: "󰅖"
                    accent: "transparent"
                    fg: ThemeBackend.overlay2
                    hint: tab.tr("Clear", "Очистить")
                    onClicked: { searchField.text = ""; searchField.forceActiveFocus(); }
                }
                Btn {
                    objectName: "searchButton"
                    implicitHeight: tab.s(36)
                    icon: "󰍉"
                    label: tab.tr("Search", "Найти")
                    accent: ThemeBackend.mauve
                    fg: ThemeBackend.crust
                    active: searchField.text.trim() !== ""
                    onClicked: { WallpaperSearch.search(searchField.text); tab.view = "search"; }
                }
            }
        }

        // recent searches (stored only on this computer)
        Flow {
            Layout.fillWidth: true
            spacing: tab.s(6)
            visible: WallpaperSearch.prefs.remember && WallpaperSearch.history.length > 0 && tab.view === "search" && (WallpaperSearch.query === "" || searchField.activeFocus)
            GroupLabel { text: tab.tr("Recent", "Недавние") }
            Repeater {
                model: WallpaperSearch.history.slice(0, 10)
                delegate: Rectangle {
                    id: hchip
                    required property string modelData
                    implicitHeight: tab.s(28)
                    implicitWidth: hRow.implicitWidth + tab.s(16)
                    radius: height / 2
                    color: hMa.containsMouse ? Qt.alpha(ThemeBackend.text, 0.08) : Qt.alpha(ThemeBackend.surface0, 0.55)
                    Row {
                        id: hRow
                        anchors.centerIn: parent
                        spacing: tab.s(6)
                        Icon { text: "󰋚"; font.pixelSize: tab.s(12); color: ThemeBackend.overlay1; anchors.verticalCenter: parent.verticalCenter }
                        Txt { text: hchip.modelData; anchors.verticalCenter: parent.verticalCenter; width: Math.min(implicitWidth, tab.s(220)) }
                        Icon {
                            text: "󰅖"; font.pixelSize: tab.s(11); color: xMa.containsMouse ? ThemeBackend.red : ThemeBackend.overlay1
                            anchors.verticalCenter: parent.verticalCenter
                            MouseArea { id: xMa; anchors.fill: parent; anchors.margins: -tab.s(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: WallpaperSearch.forgetQuery(hchip.modelData) }
                        }
                    }
                    MouseArea {
                        id: hMa
                        anchors.fill: parent
                        anchors.rightMargin: tab.s(22)
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { searchField.text = hchip.modelData; WallpaperSearch.search(hchip.modelData); }
                    }
                }
            }
            Chip { label: tab.tr("Clear history", "Очистить историю"); tint: ThemeBackend.red; onClicked: WallpaperSearch.clearHistory() }
        }

        // filters
        Rectangle {
            Layout.fillWidth: true
            visible: tab.view === "search"
            implicitHeight: filterFlow.implicitHeight + tab.s(16)
            radius: tab.s(12)
            color: Qt.alpha(ThemeBackend.surface0, 0.38)
            Flow {
                id: filterFlow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: tab.s(10)
                spacing: tab.s(6)
                GroupLabel { text: tab.tr("Type", "Тип") }
                Repeater {
                    model: [["all", "All", "Все"], ["image", "Images", "Картинки"], ["animated", "Animated", "Анимация"], ["video", "Videos", "Видео"]]
                    delegate: Chip {
                        required property var modelData
                        objectName: "kind_" + modelData[0]
                        label: tab.tr(modelData[1], modelData[2])
                        on: WallpaperSearch.kind === modelData[0]
                        onClicked: WallpaperSearch.setKind(modelData[0])
                    }
                }
                Item { width: tab.s(10); height: 1 }
                GroupLabel { text: tab.tr("Min. resolution", "Мин. разрешение") }
                Repeater {
                    model: WallpaperSearch.resOptions
                    delegate: Chip {
                        required property string modelData
                        objectName: "res_" + modelData
                        label: WallpaperSearch.resOptionLabel(modelData)
                        on: WallpaperSearch.prefs.minRes === modelData
                        tint: ThemeBackend.blue
                        onClicked: WallpaperSearch.setFilter("minRes", modelData)
                    }
                }
                Item { width: tab.s(10); height: 1 }
                GroupLabel { text: tab.tr("Sort", "Сортировка") }
                Repeater {
                    model: WallpaperSearch.sortOptions
                    delegate: Chip {
                        required property string modelData
                        objectName: "sort_" + modelData
                        label: WallpaperSearch.sortLabel(modelData)
                        on: WallpaperSearch.prefs.sort === modelData
                        tint: ThemeBackend.teal
                        onClicked: WallpaperSearch.setFilter("sort", modelData)
                    }
                }
                Item { width: tab.s(10); height: 1 }
                Toggle {
                    objectName: "safeToggle"
                    on: WallpaperSearch.prefs.safe
                    label: tab.tr("Safe Search — hide explicit content", "Safe Search — скрывать откровенный контент")
                    onToggled: WallpaperSearch.setFilter("safe", !WallpaperSearch.prefs.safe)
                }
            }
        }

        // translation and sort notes
        Flow {
            Layout.fillWidth: true
            spacing: tab.s(8)
            readonly property bool cyr: /[Ѐ-ӿ]/.test(WallpaperSearch.query)
            visible: tab.view === "search" && (WallpaperSearch.translated !== "" || WallpaperSearch.translateError !== "" || WallpaperSearch.prefs.sort === "resolution" || (!WallpaperSearch.prefs.translate && cyr))
            Txt {
                visible: WallpaperSearch.translated !== ""
                color: ThemeBackend.subtext1
                text: tab.tr("Translated for sources that only understand English: ", "Для источников, понимающих только английский, запрос переведён: ") + "“" + WallpaperSearch.translated + "”" + tab.tr(" (Pexels and Pixabay get your original text)", " (Pexels и Pixabay получают исходный текст)")
                height: tab.s(22); verticalAlignment: Text.AlignVCenter
            }
            Txt {
                visible: WallpaperSearch.translated !== ""
                text: tab.tr("Search without translation", "Искать без перевода")
                color: ThemeBackend.blue
                font.underline: true
                height: tab.s(22); verticalAlignment: Text.AlignVCenter
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: WallpaperSearch.searchWithoutTranslation() }
            }
            Txt {
                visible: WallpaperSearch.translateError !== ""
                color: ThemeBackend.peach
                text: tab.tr("Translation unavailable (", "Перевод недоступен (") + WallpaperSearch.translateError + tab.tr("); your original text was sent.", "); отправлен исходный текст.")
                height: tab.s(22); verticalAlignment: Text.AlignVCenter
            }
            Txt {
                visible: !WallpaperSearch.prefs.translate && parent.cyr
                color: ThemeBackend.subtext1
                text: tab.tr("Translation is off: every source gets your text as typed.", "Перевод выключен: все источники получают текст как есть.")
                height: tab.s(22); verticalAlignment: Text.AlignVCenter
            }
            Txt {
                visible: !WallpaperSearch.prefs.translate && parent.cyr
                text: tab.tr("Turn translation on", "Включить перевод")
                color: ThemeBackend.blue
                font.underline: true
                height: tab.s(22); verticalAlignment: Text.AlignVCenter
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: WallpaperSearch.setFilter("translate", true) }
            }
            Txt {
                visible: WallpaperSearch.prefs.sort === "resolution"
                color: ThemeBackend.subtext0
                text: tab.tr("Highest resolution first within each loaded page — the sources themselves cannot sort by resolution.", "Сначала самые большие в пределах каждой загруженной страницы — сами источники не умеют сортировать по разрешению.")
                height: tab.s(22); verticalAlignment: Text.AlignVCenter
            }
        }

        // per-source status
        ColumnLayout {
            Layout.fillWidth: true
            spacing: tab.s(4)
            visible: tab.view === "search" && WallpaperSearch.plan.length > 0
            Flow {
                Layout.fillWidth: true
                spacing: tab.s(6)
                Repeater {
                    model: WallpaperSearch.plan
                    delegate: Rectangle {
                        id: sChip
                        required property var modelData
                        readonly property var st: WallpaperSearch.statusBySource[modelData.source] || null
                        readonly property bool waiting: st === null
                        objectName: "status_" + modelData.source
                        implicitHeight: tab.s(26)
                        implicitWidth: sRow.implicitWidth + tab.s(18)
                        radius: height / 2
                        color: Qt.alpha(tab.statusTint(st), 0.12)
                        border.width: 1
                        border.color: Qt.alpha(tab.statusTint(st), 0.45)
                        Row {
                            id: sRow
                            anchors.centerIn: parent
                            spacing: tab.s(6)
                            Rectangle {
                                width: tab.s(7); height: width; radius: width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: tab.statusTint(sChip.st)
                                SequentialAnimation on opacity {
                                    running: sChip.waiting && WallpaperSearch.searching
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.25; duration: 450 }
                                    NumberAnimation { to: 1; duration: 450 }
                                }
                            }
                            Txt {
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: tab.s(11)
                                text: sChip.waiting ? WallpaperSearch.sourceLabel(sChip.modelData.source) + " · " + tab.tr("searching…", "поиск…") : tab.statusText(sChip.st)
                            }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tab.showDetails = !tab.showDetails }
                    }
                }
                Txt {
                    height: tab.s(26); verticalAlignment: Text.AlignVCenter
                    text: tab.showDetails ? tab.tr("hide details", "скрыть подробности") : tab.tr("details", "подробнее")
                    color: ThemeBackend.blue; font.pixelSize: tab.s(11); font.underline: true
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tab.showDetails = !tab.showDetails }
                }
            }
            Repeater {
                model: tab.showDetails ? Object.keys(WallpaperSearch.statusBySource).map(k => WallpaperSearch.statusBySource[k]) : []
                delegate: Txt {
                    required property var modelData
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: tab.s(11)
                    color: modelData.error ? ThemeBackend.red : ThemeBackend.subtext0
                    text: "• " + tab.statusDetail(modelData)
                }
            }
        }

        // free API key hint
        Rectangle {
            Layout.fillWidth: true
            visible: tab.view === "search" && tab.keyMissing.length > 0 && !WallpaperSearch.prefs.keyHintDismissed
            implicitHeight: keyHintRow.implicitHeight + tab.s(14)
            radius: tab.s(12)
            color: Qt.alpha(ThemeBackend.blue, 0.1)
            border.width: 1
            border.color: Qt.alpha(ThemeBackend.blue, 0.35)
            RowLayout {
                id: keyHintRow
                anchors.fill: parent
                anchors.margins: tab.s(7)
                anchors.leftMargin: tab.s(12)
                spacing: tab.s(10)
                Icon { text: "󰌆"; color: ThemeBackend.blue }
                Txt {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: tab.keyMissing.map(n => WallpaperSearch.sourceLabel(n)).join(", ")
                          + tab.tr(" also search with your own free API key — Pexels and Pixabay add photos and MP4 videos (up to 4K), Giphy adds GIFs. The key stays in a private file on this computer.",
                                   " ищут с вашим собственным бесплатным API-ключом — Pexels и Pixabay добавляют фото и MP4-видео (до 4K), Giphy — GIF. Ключ хранится в личном файле на этом компьютере.")
                }
                Btn { label: tab.tr("Add keys", "Добавить ключи"); accent: Qt.alpha(ThemeBackend.blue, 0.35); onClicked: tab.showSettings = true }
                Btn { icon: "󰅖"; accent: "transparent"; fg: ThemeBackend.overlay2; hint: tab.tr("Hide", "Скрыть"); onClicked: WallpaperSearch.setPref("keyHintDismissed", true) }
            }
        }

        // offline banner
        Rectangle {
            Layout.fillWidth: true
            visible: WallpaperSearch.offline
            implicitHeight: offTxt.implicitHeight + tab.s(16)
            radius: tab.s(12)
            color: Qt.alpha(ThemeBackend.red, 0.12)
            border.width: 1
            border.color: Qt.alpha(ThemeBackend.red, 0.4)
            Txt {
                id: offTxt
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: tab.s(10)
                wrapMode: Text.Wrap
                text: tab.tr("Offline: no connection to the wallpaper sources", "Offline: нет подключения к источникам обоев") + (WallpaperSearch.offlineDetail ? " (" + WallpaperSearch.offlineDetail + ")" : "")
                      + tab.tr(". Your current wallpaper keeps running and downloaded wallpapers can still be applied. Click to check again.", ". Текущие обои продолжают работать, скачанные можно применять. Нажмите, чтобы проверить снова.")
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: WallpaperSearch.refreshStatus() }
        }

        // download progress
        Rectangle {
            Layout.fillWidth: true
            visible: WallpaperSearch.downloading
            implicitHeight: tab.s(44)
            radius: tab.s(12)
            color: Qt.alpha(ThemeBackend.surface0, 0.7)
            RowLayout {
                anchors.fill: parent
                anchors.margins: tab.s(8)
                anchors.leftMargin: tab.s(12)
                spacing: tab.s(10)
                Icon { text: "󰇚"; color: ThemeBackend.mauve }
                Txt {
                    Layout.preferredWidth: tab.s(240)
                    text: (WallpaperSearch.dlAfter === "apply" ? tab.tr("Downloading to apply: ", "Загрузка для установки: ") : tab.tr("Downloading: ", "Загрузка: ")) + (WallpaperSearch.dlItem ? (WallpaperSearch.dlItem.title || WallpaperSearch.dlItem.id) : "")
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: tab.s(6)
                    radius: height / 2
                    color: ThemeBackend.surface1
                    clip: true
                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        color: ThemeBackend.mauve
                        width: WallpaperSearch.dlTotal > 0 ? parent.width * Math.min(1, WallpaperSearch.dlDone / WallpaperSearch.dlTotal) : parent.width * 0.25
                    }
                }
                Txt { text: WallpaperSearch.fmtSize(WallpaperSearch.dlDone) + (WallpaperSearch.dlTotal > 0 ? " / " + WallpaperSearch.fmtSize(WallpaperSearch.dlTotal) : "") }
                Btn { label: tab.tr("Cancel", "Отмена"); accent: Qt.alpha(ThemeBackend.red, 0.35); onClicked: WallpaperSearch.cancelDownload() }
            }
        }

        Txt { visible: WallpaperSearch.lastError !== ""; color: ThemeBackend.red; text: WallpaperSearch.lastError; Layout.fillWidth: true; wrapMode: Text.Wrap }

        // results / library
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // empty and loading states
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width * 0.8, tab.s(560))
                spacing: tab.s(10)
                visible: tab.view === "search" && grid.count === 0
                Icon {
                    Layout.alignment: Qt.AlignHCenter
                    text: WallpaperSearch.searching ? "󰔟" : WallpaperSearch.query === "" ? "󰸉" : "󰍉"
                    font.pixelSize: tab.s(46)
                    color: Qt.alpha(ThemeBackend.mauve, 0.7)
                    RotationAnimation on rotation { running: WallpaperSearch.searching; from: 0; to: 360; duration: 1600; loops: Animation.Infinite }
                }
                Txt {
                    objectName: "emptyTitle"
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.pixelSize: tab.s(15)
                    font.weight: Font.DemiBold
                    text: WallpaperSearch.searching ? tab.tr("Searching the sources… ", "Опрашиваем источники… ") + tab.answered + " / " + tab.askedCount
                        : WallpaperSearch.query === "" ? tab.tr("Type any request in English or Russian", "Введите любой запрос на английском или русском")
                        : Object.keys(WallpaperSearch.byId).length > 0 ? tab.tr("All results are hidden by your quality filters", "Все результаты скрыты вашими фильтрами качества")
                        : tab.tr("Nothing found", "Ничего не найдено")
                }
                Txt {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: ThemeBackend.subtext0
                    visible: !WallpaperSearch.searching
                    text: WallpaperSearch.query === "" ? tab.tr("Results come live from Wallhaven, Openverse and Wikimedia Commons; with your own free keys also from Pexels, Pixabay and Giphy. Nothing is pre-made or substituted.",
                                                  "Результаты приходят напрямую из Wallhaven, Openverse и Wikimedia Commons, а с вашими бесплатными ключами — из Pexels, Pixabay и Giphy. Ничего не подставляется заранее.")
                        : tab.tr("Why: see the status of each source above (“details”). A lower minimum resolution or Safe Search off can bring more results.",
                                 "Почему — смотрите статус каждого источника выше («подробнее»). Меньшее минимальное разрешение или выключенный Safe Search могут дать больше результатов.")
                }
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: tab.s(8)
                    visible: !WallpaperSearch.searching && WallpaperSearch.query !== "" && grid.count === 0
                    Btn { visible: WallpaperSearch.effectiveMinRes !== "any"; label: tab.tr("Try any resolution", "Любое разрешение"); onClicked: WallpaperSearch.setFilter("minRes", "any") }
                    Btn { visible: WallpaperSearch.kind !== "all"; label: tab.tr("All types", "Все типы"); onClicked: WallpaperSearch.setKind("all") }
                }
            }

            GridView {
                id: grid
                objectName: "resultsGrid"
                anchors.fill: parent
                visible: tab.view === "search"
                clip: true
                model: WallpaperSearch.results
                readonly property int cols: Math.max(1, Math.floor(width / tab.s(268)))
                cellWidth: Math.floor(width / cols)
                cellHeight: Math.round((cellWidth - tab.s(12)) * 0.5625) + tab.s(70)
                cacheBuffer: cellHeight
                boundsBehavior: Flickable.StopAtBounds
                C.ScrollBar.vertical: C.ScrollBar { policy: C.ScrollBar.AsNeeded }
                // Infinite scroll: the next page is requested two rows before the end.
                onContentYChanged: if (contentHeight > height && contentY + height > contentHeight - cellHeight * 2) WallpaperSearch.loadMore()
                footer: Item {
                    width: grid.width
                    height: grid.count > 0 ? tab.s(56) : 0
                    Row {
                        anchors.centerIn: parent
                        spacing: tab.s(8)
                        visible: grid.count > 0
                        Icon { visible: WallpaperSearch.searching; text: "󰔟"; color: ThemeBackend.overlay2; RotationAnimation on rotation { running: WallpaperSearch.searching; from: 0; to: 360; duration: 1400; loops: Animation.Infinite } }
                        Txt { visible: WallpaperSearch.searching; text: tab.tr("Loading more…", "Загружаем ещё…"); color: ThemeBackend.subtext0; anchors.verticalCenter: parent.verticalCenter }
                        Btn { visible: !WallpaperSearch.searching && WallpaperSearch.hasMore; label: tab.tr("Load more", "Загрузить ещё"); onClicked: WallpaperSearch.loadMore() }
                        Txt { visible: !WallpaperSearch.searching && !WallpaperSearch.hasMore; text: tab.tr("End of results", "Больше результатов нет"); color: ThemeBackend.overlay1; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                delegate: SearchCard {
                    required property string rid
                    width: grid.cellWidth
                    height: grid.cellHeight
                    tab: tabRoot
                    r: WallpaperSearch.byId[rid] || null
                }
            }

            // downloaded / offline library
            GridView {
                id: libGrid
                objectName: "libraryGrid"
                anchors.fill: parent
                visible: tab.view === "library"
                clip: true
                model: WallpaperSearch.library
                readonly property int cols: Math.max(1, Math.floor(width / tab.s(240)))
                cellWidth: Math.floor(width / cols)
                cellHeight: Math.round((cellWidth - tab.s(12)) * 0.5625) + tab.s(96)
                boundsBehavior: Flickable.StopAtBounds
                C.ScrollBar.vertical: C.ScrollBar {}
                header: Txt {
                    width: libGrid.width
                    height: tab.s(30)
                    color: ThemeBackend.subtext0
                    text: WallpaperSearch.library.length === 0 ? tab.tr("No wallpapers downloaded yet. Files are saved to ", "Скачанных обоев пока нет. Файлы сохраняются в ") + WallpaperSearch.downloadDir
                                                 : tab.tr("Your wallpapers — downloads first. Works offline.", "Ваши обои — сначала скачанные. Работает и без интернета.")
                }
                delegate: Item {
                    id: lcell
                    required property var modelData
                    readonly property var it: modelData
                    width: libGrid.cellWidth
                    height: libGrid.cellHeight
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: tab.s(6)
                        radius: tab.s(12)
                        color: Qt.alpha(ThemeBackend.surface0, 0.55)
                        border.width: 1
                        border.color: lHover.hovered ? Qt.alpha(ThemeBackend.mauve, 0.7) : Qt.alpha(ThemeBackend.surface2, 0.3)
                        clip: true
                        HoverHandler { id: lHover }
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: tab.s(6)
                            spacing: tab.s(4)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.round(width * 0.5625)
                                radius: tab.s(8)
                                color: ThemeBackend.mantle
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    visible: lcell.it.kind !== "video"
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: tab.s(360)
                                    source: lcell.it.kind !== "video" ? Caching.fileUrl(lcell.it.path) : ""
                                }
                                Icon { anchors.centerIn: parent; visible: lcell.it.kind === "video"; text: "󰕧"; font.pixelSize: tab.s(34); color: ThemeBackend.overlay1 }
                                Row {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.margins: tab.s(6)
                                    spacing: tab.s(4)
                                    Badge { label: lcell.it.format.toUpperCase(); tint: ThemeBackend.blue; solid: true }
                                    Badge { visible: lcell.it.edited; label: tab.tr("EDITED", "ИЗМЕНЕНО"); tint: ThemeBackend.peach; solid: true }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tab.openLocalPreview(lcell.it) }
                            }
                            Txt { Layout.fillWidth: true; text: lcell.it.title; font.weight: Font.DemiBold }
                            Txt { Layout.fillWidth: true; color: ThemeBackend.subtext0; font.pixelSize: tab.s(11); text: (lcell.it.source || tab.tr("local file", "локальный файл")) + " · " + WallpaperSearch.fmtSize(lcell.it.size) }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: tab.s(4)
                                Btn { Layout.fillWidth: true; icon: "󰈈"; hint: tab.tr("Preview", "Просмотр"); onClicked: tab.openLocalPreview(lcell.it) }
                                Btn { Layout.fillWidth: true; icon: "󰏫"; hint: tab.tr("Edit in Wallpaper Studio", "Изменить в Wallpaper Studio"); active: WallpaperSearch.ffmpegOk; onClicked: tab.studioPath = lcell.it.path }
                                Btn { Layout.fillWidth: true; icon: "󰸉"; label: tab.tr("Apply", "Применить"); accent: ThemeBackend.mauve; fg: ThemeBackend.crust; onClicked: tab.applyPath(lcell.it.path) }
                            }
                        }
                    }
                }
            }
        }

        // where Apply goes
        RowLayout {
            Layout.fillWidth: true
            spacing: tab.s(6)
            GroupLabel { text: tab.tr("Apply to", "Применять на") }
            Chip { label: tab.tr("All monitors", "Все мониторы"); on: WallpaperSearch.monitor === "all"; onClicked: WallpaperSearch.monitor = "all" }
            Repeater {
                model: Quickshell.screens
                delegate: Chip {
                    required property var modelData
                    label: modelData.name
                    on: WallpaperSearch.monitor === modelData.name
                    onClicked: WallpaperSearch.monitor = modelData.name
                }
            }
            Item { Layout.fillWidth: true }
            Txt {
                Layout.maximumWidth: tab.width * 0.45
                color: ThemeBackend.overlay1
                font.pixelSize: tab.s(11)
                elide: Text.ElideMiddle
                text: tab.tr("Saved to ", "Сохраняется в ") + WallpaperSearch.downloadDir
            }
        }
    }

    // ---------------------------------------------------------------- settings sheet
    Rectangle {
        objectName: "settingsSheet"
        anchors.fill: parent
        visible: tab.showSettings
        enabled: visible
        color: Qt.alpha(ThemeBackend.crust, 0.55)
        z: 40
        MouseArea { anchors.fill: parent; onClicked: tab.showSettings = false; onWheel: (w) => w.accepted = true }
        Keys.onEscapePressed: (ev) => { tab.showSettings = false; ev.accepted = true; }
        onVisibleChanged: if (visible) forceActiveFocus()
        SearchSettings {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: tab.s(10)
            width: Math.min(parent.width - tab.s(20), tab.s(470))
            tab: tabRoot
        }
    }

    // ---------------------------------------------------------------- toast
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: tab.s(52)
        visible: opacity > 0
        opacity: WallpaperSearch.toast !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        width: Math.min(parent.width - tab.s(40), toastTxt.implicitWidth + tab.s(32))
        height: toastTxt.implicitHeight + tab.s(18)
        radius: tab.s(12)
        color: Qt.alpha(ThemeBackend.crust, 0.94)
        border.width: 1
        border.color: Qt.alpha(ThemeBackend.surface2, 0.5)
        z: 80
        Text {
            id: toastTxt
            objectName: "toast"
            anchors.centerIn: parent
            width: Math.min(implicitWidth, tab.width - tab.s(72))
            text: WallpaperSearch.toast
            color: ThemeBackend.text
            font.family: ThemeBackend.fontFamily
            font.pixelSize: tab.s(12)
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
    }

    // ---------------------------------------------------------------- overlays (loaded by URL)
    onPreviewEntryChanged: {
        if (previewEntry === null) previewLoader.source = "";
        else if (previewLoader.status === Loader.Null) previewLoader.setSource(Qt.resolvedUrl("SearchPreview.qml"), { "hub": tab });
    }
    onStudioPathChanged: {
        if (studioPath === "") studioLoader.source = "";
        else if (studioLoader.status === Loader.Null) studioLoader.setSource(Qt.resolvedUrl("WallpaperStudio.qml"), { "hub": tab });
    }
    Loader {
        id: previewLoader
        objectName: "previewLoader"
        anchors.fill: parent
        z: 60
        onStatusChanged: {
            if (status === Loader.Error) {
                WallpaperSearch.notify(tab.tr("Preview failed to load (is QtMultimedia installed?)", "Просмотр не загрузился (установлен ли QtMultimedia?)"));
                tab.previewEntry = null;
            }
        }
    }
    Loader {
        id: studioLoader
        objectName: "studioLoader"
        anchors.fill: parent
        z: 70
        onStatusChanged: {
            if (status === Loader.Error) {
                WallpaperSearch.notify(tab.tr("Wallpaper Studio failed to load (is QtMultimedia installed?)", "Wallpaper Studio не загрузилась (установлен ли QtMultimedia?)"));
                tab.studioPath = "";
            }
        }
    }
}
