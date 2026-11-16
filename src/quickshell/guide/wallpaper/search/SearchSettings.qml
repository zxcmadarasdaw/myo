import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as C
import QtQuick.Dialogs as D
import "../../../"

// Right-hand sheet of Search Wallpapers: sources (with what each one really
// supports), the user's own API keys, translation, history and quality filters.
Rectangle {
    id: sheet
    property var tab: null
    function s(v) { return tab ? tab.s(v) : v; }
    function tr(en, ru) { return WallpaperSearch.tr(en, ru); }

    radius: s(16)
    color: ThemeBackend.base
    border.width: 1
    border.color: Qt.alpha(ThemeBackend.surface2, 0.5)
    // Swallow clicks so they do not reach the dim layer that closes the sheet.
    MouseArea { anchors.fill: parent; onWheel: (w) => w.accepted = false }

    component Txt: Text {
        color: ThemeBackend.text
        font.family: ThemeBackend.fontFamily
        font.pixelSize: sheet.s(12)
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
    component Head: Txt {
        font.pixelSize: sheet.s(13)
        font.weight: Font.Bold
        Layout.topMargin: sheet.s(8)
    }
    // Drawn here so the sheet stays matte and dark under any Qt Quick Controls style.
    component Check: C.CheckBox {
        id: chk
        font.family: ThemeBackend.fontFamily
        font.pixelSize: sheet.s(12)
        Layout.fillWidth: true
        spacing: sheet.s(10)
        indicator: Rectangle {
            x: chk.leftPadding
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: sheet.s(18)
            implicitHeight: sheet.s(18)
            radius: sheet.s(5)
            color: chk.checked ? ThemeBackend.mauve : Qt.alpha(ThemeBackend.surface1, 0.9)
            border.width: chk.checked ? 0 : 1
            border.color: chk.hovered ? Qt.alpha(ThemeBackend.mauve, 0.7) : Qt.alpha(ThemeBackend.overlay0, 0.6)
            Behavior on color { ColorAnimation { duration: 110 } }
            Text {
                anchors.centerIn: parent
                visible: chk.checked
                text: "󰄬"
                color: ThemeBackend.crust
                font.family: ThemeBackend.iconFont
                font.pixelSize: sheet.s(13)
            }
        }
        contentItem: Text {
            leftPadding: chk.indicator.width + chk.spacing
            text: chk.text
            font: chk.font
            color: chk.enabled ? ThemeBackend.text : ThemeBackend.overlay1
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
        }
    }
    component SmallBtn: Rectangle {
        id: sb
        property string label: ""
        property bool active: true
        property color accent: ThemeBackend.surface1
        signal clicked()
        implicitHeight: sheet.s(28)
        implicitWidth: sbText.implicitWidth + sheet.s(18)
        radius: sheet.s(8)
        opacity: active ? 1 : 0.45
        color: sbMa.containsMouse && active ? Qt.lighter(accent, 1.15) : accent
        Text { id: sbText; anchors.centerIn: parent; text: sb.label; color: ThemeBackend.text; font.family: ThemeBackend.fontFamily; font.pixelSize: sheet.s(12); font.weight: Font.DemiBold }
        MouseArea { id: sbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (sb.active) sb.clicked() }
    }

    function capLine(name) {
        let c = WallpaperSearch.caps[name];
        if (!c) return "";
        let kinds = c.kinds.map(k => k === "image" ? tr("images", "картинки") : k === "animated" ? tr("animations", "анимации") : tr("video", "видео")).join(", ");
        let safe = c.safe === "filter" ? tr("own content filter", "свой фильтр контента")
                 : c.safe === "policy" ? tr("no explicit content by site rules", "откровенный контент запрещён правилами сайта")
                 : c.safe === "local" ? tr("local files", "локальные файлы")
                 : tr("no content filter — skipped while Safe Search is on", "нет фильтра контента — пропускается при включённом Safe Search");
        let sorts = c.sorts.filter(x => x === "newest" || x === "popular").map(x => WallpaperSearch.sortLabel(x).toLowerCase());
        let key = c.key === "required" ? tr("needs your API key", "нужен ваш API-ключ")
                : c.key === "optional" ? tr("key optional", "ключ необязателен") : tr("no key", "без ключа");
        return kinds + (c.formats.length ? " · " + c.formats.join("/").toUpperCase() : "") + " · " + safe + " · " + key
             + (sorts.length ? " · " + tr("sorts: ", "сортировка: ") + sorts.join(", ") : "")
             + " · " + tr("limit: ", "лимит: ") + c.limits;
    }

    D.FolderDialog {
        id: folderPicker
        title: sheet.tr("Add a wallpaper folder", "Добавить папку обоев")
        onAccepted: WallpaperSearch.editCustomSources("add", "folders", String(selectedFolder))
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: sheet.s(14)
        spacing: sheet.s(6)

        RowLayout {
            Layout.fillWidth: true
            Txt { Layout.fillWidth: true; text: sheet.tr("Search Wallpapers settings", "Настройки поиска обоев"); font.pixelSize: sheet.s(16); font.weight: Font.Bold }
            SmallBtn { label: "✕"; onClicked: sheet.tab.showSettings = false }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            C.ScrollBar.vertical: C.ScrollBar {}

            ColumnLayout {
                id: col
                width: parent.width - sheet.s(10)
                spacing: sheet.s(6)

                Head { text: sheet.tr("Sources", "Источники") }
                Repeater {
                    model: WallpaperSearch.sourceNames
                    delegate: Rectangle {
                        id: srow
                        required property string modelData
                        readonly property var cap: WallpaperSearch.caps[modelData] || null
                        readonly property bool needsKey: cap && cap.key !== "none"
                        Layout.fillWidth: true
                        implicitHeight: srcCol.implicitHeight + sheet.s(14)
                        radius: sheet.s(10)
                        color: Qt.alpha(ThemeBackend.surface0, 0.55)
                        ColumnLayout {
                            id: srcCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: sheet.s(8)
                            spacing: sheet.s(4)
                            RowLayout {
                                Layout.fillWidth: true
                                Check {
                                    objectName: "source_" + srow.modelData
                                    text: WallpaperSearch.sourceLabel(srow.modelData) + (srow.needsKey ? (WallpaperSearch.keys[srow.modelData] ? "  󰌆 " + sheet.tr("key saved", "ключ сохранён") : (srow.cap.key === "required" ? "  · " + sheet.tr("key needed", "нужен ключ") : "")) : "")
                                    checked: WallpaperSearch.prefs.sources[srow.modelData] !== false
                                    onToggled: WallpaperSearch.setSourceEnabled(srow.modelData, checked)
                                }
                            }
                            Txt { Layout.fillWidth: true; visible: text !== ""; color: ThemeBackend.subtext0; font.pixelSize: sheet.s(11); text: sheet.capLine(srow.modelData) }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: srow.needsKey
                                spacing: sheet.s(6)
                                C.TextField {
                                    id: keyField
                                    Layout.fillWidth: true
                                    echoMode: TextInput.Password
                                    placeholderText: WallpaperSearch.keys[srow.modelData] ? sheet.tr("saved — paste a new key to replace", "сохранён — вставьте новый для замены") : sheet.tr("paste your API key", "вставьте ваш API-ключ")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: sheet.s(12)
                                    color: ThemeBackend.text
                                    placeholderTextColor: ThemeBackend.overlay1
                                    selectionColor: Qt.alpha(ThemeBackend.mauve, 0.45)
                                    selectedTextColor: ThemeBackend.text
                                    leftPadding: sheet.s(10)
                                    rightPadding: sheet.s(10)
                                    background: Rectangle {
                                        implicitHeight: sheet.s(32)
                                        radius: sheet.s(8)
                                        color: Qt.alpha(ThemeBackend.crust, 0.7)
                                        border.width: 1
                                        border.color: keyField.activeFocus ? Qt.alpha(ThemeBackend.mauve, 0.8) : Qt.alpha(ThemeBackend.surface2, 0.5)
                                    }
                                    onAccepted: if (text.trim() !== "") { WallpaperSearch.saveKey(srow.modelData, text.trim()); text = ""; }
                                }
                                SmallBtn { label: sheet.tr("Save", "Сохранить"); active: keyField.text.trim() !== ""; accent: Qt.alpha(ThemeBackend.mauve, 0.45); onClicked: { WallpaperSearch.saveKey(srow.modelData, keyField.text.trim()); keyField.text = ""; } }
                                SmallBtn { label: sheet.tr("Remove", "Удалить"); visible: !!WallpaperSearch.keys[srow.modelData]; onClicked: WallpaperSearch.saveKey(srow.modelData, "") }
                                SmallBtn { label: sheet.tr("Get a key", "Получить"); visible: !!(srow.cap && srow.cap.keyUrl); onClicked: Qt.openUrlExternally(srow.cap.keyUrl) }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: srow.modelData !== "local"
                                SmallBtn {
                                    label: sheet.tr("Test connection", "Проверить подключение")
                                    active: !WallpaperSearch.checkingSource && (!srow.needsKey || srow.cap.key === "optional" || !!WallpaperSearch.keys[srow.modelData])
                                    onClicked: WallpaperSearch.checkSource(srow.modelData)
                                }
                                Txt {
                                    Layout.fillWidth: true
                                    text: WallpaperSearch.sourceChecks[srow.modelData] || ""
                                    color: ThemeBackend.subtext0
                                }
                            }
                        }
                    }
                }
                Txt {
                    Layout.fillWidth: true
                    color: ThemeBackend.subtext0
                    font.pixelSize: sheet.s(11)
                    text: sheet.tr("API keys are saved in ~/.config/serpantinum/secrets/wallpaper_hub.json (mode 600). Check the provider’s plan for quotas and pricing.",
                                   "Ключи хранятся в ~/.config/serpantinum/secrets/wallpaper_hub.json (права 600). Лимиты и цены зависят от тарифа провайдера.")
                }
                Head { text: sheet.tr("Wallpaper folders", "Папки с обоями") }
                SmallBtn {
                    label: sheet.tr("Add folder", "Выбрать папку")
                    active: !WallpaperSearch.editingSources
                    onClicked: folderPicker.open()
                }
                Repeater {
                    model: WallpaperSearch.customSources.folders
                    delegate: RowLayout {
                        required property string modelData
                        Layout.fillWidth: true
                        Txt { Layout.fillWidth: true; text: modelData; color: ThemeBackend.subtext0 }
                        SmallBtn {
                            label: sheet.tr("Remove", "Убрать")
                            active: !WallpaperSearch.editingSources
                            onClicked: WallpaperSearch.editCustomSources("remove", "folders", modelData)
                        }
                    }
                }
                Head { text: sheet.tr("Direct URL or feed", "Прямая ссылка или лента") }
                RowLayout {
                    Layout.fillWidth: true
                    C.TextField {
                        id: customUrl
                        Layout.fillWidth: true
                        placeholderText: "https://…"
                        onAccepted: if (text.trim() !== "" && !WallpaperSearch.editingSources) {
                            WallpaperSearch.editCustomSources("add", "urls", text.trim());
                            text = "";
                        }
                    }
                    SmallBtn {
                        label: sheet.tr("Add", "Добавить")
                        active: customUrl.text.trim() !== "" && !WallpaperSearch.editingSources
                        onClicked: customUrl.accepted()
                    }
                }
                Repeater {
                    model: WallpaperSearch.customSources.urls
                    delegate: RowLayout {
                        required property string modelData
                        Layout.fillWidth: true
                        Txt { Layout.fillWidth: true; text: modelData; color: ThemeBackend.subtext0 }
                        SmallBtn {
                            label: sheet.tr("Remove", "Убрать")
                            active: !WallpaperSearch.editingSources
                            onClicked: WallpaperSearch.editCustomSources("remove", "urls", modelData)
                        }
                    }
                }

                Head { text: sheet.tr("Search", "Поиск") }
                Check {
                    text: sheet.tr("Include results with unknown resolution", "Показывать результаты с неизвестным разрешением")
                    checked: WallpaperSearch.prefs.includeUnknown
                    onToggled: WallpaperSearch.setFilter("includeUnknown", checked)
                }
                Check {
                    objectName: "translateCheck"
                    text: sheet.tr("Translate Russian queries for sources that only understand English (the translation is always shown)", "Переводить русские запросы для источников, понимающих только английский (перевод всегда показывается)")
                    checked: WallpaperSearch.prefs.translate
                    onToggled: WallpaperSearch.setFilter("translate", checked)
                }
                Check {
                    text: sheet.tr("Remember my searches on this computer", "Запоминать мои запросы на этом компьютере")
                    checked: WallpaperSearch.prefs.remember
                    onToggled: WallpaperSearch.setPref("remember", checked)
                }
                RowLayout {
                    Layout.fillWidth: true
                    Txt { Layout.fillWidth: true; color: ThemeBackend.subtext0; font.pixelSize: sheet.s(11); text: sheet.tr("History is a private local file (mode 600), not part of settings.json or Themess.", "История — личный локальный файл (права 600), не входит в settings.json и Themess.") }
                    SmallBtn { label: sheet.tr("Clear history", "Очистить историю"); active: WallpaperSearch.history.length > 0; onClicked: WallpaperSearch.clearHistory() }
                }
                Txt {
                    Layout.fillWidth: true
                    color: ThemeBackend.subtext0
                    font.pixelSize: sheet.s(11)
                    text: sheet.tr("Safe Search uses each source's own filter: Wallhaven SFW purity, Openverse mature=false, Pixabay safesearch, Giphy rating PG. Pexels allows no explicit content at all. Wikimedia Commons has no filter, so it only takes part when Safe Search is off.",
                                   "Safe Search использует фильтр каждого источника: Wallhaven SFW, Openverse mature=false, Pixabay safesearch, Giphy рейтинг PG. Pexels не допускает откровенный контент вообще. У Wikimedia Commons фильтра нет, поэтому он участвует только при выключенном Safe Search.")
                }

                Head { text: sheet.tr("Original Quality Checker", "Проверка качества оригинала") }
                Txt { Layout.fillWidth: true; color: ThemeBackend.subtext0; font.pixelSize: sheet.s(11); text: sheet.tr("All off by default — nothing is hidden unless you enable it.", "По умолчанию всё выключено — ничего не скрывается без вашего решения.") }
                Check { text: sheet.tr("Hide likely upscales (among files already checked)", "Скрывать вероятные апскейлы (среди уже проверенных)"); checked: WallpaperSearch.prefs.hideUpscales; onToggled: WallpaperSearch.setLocalFilter("hideUpscales", checked) }
                Check { text: sheet.tr("Only results with known resolution and file size", "Только результаты с известным разрешением и размером"); checked: WallpaperSearch.prefs.knownOnly; onToggled: WallpaperSearch.setLocalFilter("knownOnly", checked) }
                Flow {
                    Layout.fillWidth: true
                    spacing: sheet.s(8)
                    Txt { height: sheet.s(36); verticalAlignment: Text.AlignVCenter; wrapMode: Text.NoWrap; text: sheet.tr("Min. video bitrate, Mbit/s (0 = off)", "Мин. битрейт видео, Мбит/с (0 = выкл.)") }
                    C.SpinBox { palette.base: ThemeBackend.surface0; palette.text: ThemeBackend.text; palette.button: ThemeBackend.surface1; palette.buttonText: ThemeBackend.text; palette.mid: ThemeBackend.surface2; palette.window: ThemeBackend.surface0; from: 0; to: 200; value: WallpaperSearch.prefs.minBitrateMbps || 0; editable: true; onValueModified: WallpaperSearch.setLocalFilter("minBitrateMbps", value) }
                    Txt { height: sheet.s(36); verticalAlignment: Text.AlignVCenter; wrapMode: Text.NoWrap; text: sheet.tr("Download size limit, MB", "Лимит загрузки, МБ") }
                    C.SpinBox { palette.base: ThemeBackend.surface0; palette.text: ThemeBackend.text; palette.button: ThemeBackend.surface1; palette.buttonText: ThemeBackend.text; palette.mid: ThemeBackend.surface2; palette.window: ThemeBackend.surface0; from: 20; to: 4000; stepSize: 20; value: WallpaperSearch.prefs.maxDownloadMb || 400; editable: true; onValueModified: WallpaperSearch.setPref("maxDownloadMb", value) }
                }
                Txt {
                    Layout.fillWidth: true
                    color: ThemeBackend.subtext0
                    font.pixelSize: sheet.s(11)
                    text: sheet.tr("Downloads go to ", "Файлы сохраняются в ") + WallpaperSearch.downloadDir + sheet.tr(". Every file is identified by its signature and decoded with ffprobe before it is kept; nothing downloaded is ever executed.", ". Каждый файл проверяется по сигнатуре и декодируется ffprobe; скачанное никогда не запускается.")
                }
                Txt {
                    Layout.fillWidth: true
                    visible: !WallpaperSearch.ffmpegOk
                    color: ThemeBackend.red
                    text: sheet.tr("ffmpeg/ffprobe not found: file checks, quality analysis and Wallpaper Studio are unavailable (sudo dnf install ffmpeg-free).", "ffmpeg/ffprobe не найдены: проверка файлов, анализ качества и Wallpaper Studio недоступны (sudo dnf install ffmpeg-free).")
                }
            }
        }
    }
}
