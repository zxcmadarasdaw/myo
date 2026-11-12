import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Dialogs as Dialogs
import QtQuick.Layouts
import QtQuick.Window
import "../"
import "../reusables"
import "themess"

GuideTab {
    id: tab

    readonly property string outputName: Window.window && Window.window.screen ? Window.window.screen.name : ""
    readonly property var selected: Themess.packageAt(Themess.folder)
    readonly property var inspection: selected && Themess.result.folder === selected.folder
        ? Object.assign({}, selected, Themess.result) : selected
    property bool showDetails: false

    function tr(key, fallback) {
        return I18n.t("guide.themess." + key, fallback);
    }

    function compatibility(item) {
        if (item.errors.length) return tr("incompatible", "Incompatible");
        if (item.warnings.length) return tr("partial", "Partially compatible");
        return tr("compatible", "Compatible");
    }

    function openDetails(item, preview) {
        Themess.selectFolder(item.folder);
        showDetails = true;
        if (preview) Themess.run("preview", outputName, item.folder);
    }

    function componentSummary(item, kind) {
        const appearance = item.appearance || {};
        if (kind === "widgets") return (item.widgets || []).length + " · "
            + (item.widgets || []).map(widget => widget.wType + (widget.wVariant ? " / " + widget.wVariant : "")).join(", ");
        if (kind === "animations") {
            const animation = appearance.wallpaperTransition || {};
            return (animation.pool || Object.keys(animation.effects || {})).map(effect => {
                const duration = animation.effects?.[effect]?.duration;
                return effect + (duration !== undefined ? " (" + duration + " ms)" : "");
            }).join(", ") || animation.mode || "";
        }
        const section = {palette: "theme", materials: "theme", panels: "bar"}[kind] || kind;
        const values = appearance[section] || {};
        const keys = {
            palette: ["mode"], materials: ["blurStyle", "blurBackground", "borderRadius", "elementOpacity", "fontFamily"],
            panels: ["position", "style", "width", "height"], canvas: ["enabled", "wheelAction", "minimap"],
            dock: ["enabled", "position", "floating", "autohide"],
            launcher: ["position", "width", "itemCount"], notifications: ["position", "sound", "dnd"]
        }[kind] || [];
        return keys.filter(key => values[key] !== undefined).map(key => key + " = " + values[key]).join(" · ");
    }

    function refresh() { Themess.run("catalog", outputName); }

    onIsCurrentChanged: {
        if (isCurrent) Qt.callLater(tab.refresh);
    }
    Component.onCompleted: {
        if (isCurrent) Qt.callLater(tab.refresh);
    }
    onOutputNameChanged: {
        if (isCurrent) Qt.callLater(tab.refresh);
    }

    component Copy: Label {
        color: ThemeBackend.text
        font.family: ThemeBackend.fontFamily
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }

    component ActionButton: Basic.Button {
        id: button
        font.family: ThemeBackend.fontFamily
        palette.button: ThemeBackend.surface1
        palette.buttonText: ThemeBackend.text
        palette.highlight: ThemeBackend.mauve
        background: Rectangle {
            implicitHeight: Scaler.s(32)
            radius: Math.min(Scaler.s(10), ThemeBackend.borderRadius)
            color: button.highlighted ? Qt.alpha(ThemeBackend.mauve, button.hovered ? 0.38 : 0.25)
                : (button.hovered ? ThemeBackend.surface1 : ThemeBackend.surface0)
            opacity: button.enabled ? 1 : 0.45
            border.width: button.visualFocus ? 1 : 0
            border.color: ThemeBackend.mauve
            Behavior on color { ColorAnimation { duration: 140 } }
        }
    }

    Dialogs.FolderDialog {
        id: picker
        objectName: "themessFolderDialog"
        parentWindow: tab.Window.window
        title: tab.tr("import", "Import Folder")
        options: Dialogs.FolderDialog.ReadOnly
        onAccepted: {
            const path = Themess.localPath(selectedFolder);
            if (path && Themess.run("import", tab.outputName, path)) {
                query.clear();
                filter.currentIndex = 0;
                tab.showDetails = true;
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Scaler.s(16)
        spacing: Scaler.s(10)

        Copy {
            Layout.fillWidth: true
            text: "Themess"
            font.pixelSize: Scaler.s(28)
            font.bold: true
        }

        Copy {
            Layout.fillWidth: true
            color: ThemeBackend.subtext1
            text: Themess.active ? tab.tr("active", "Active package") + " · " + Themess.active.name
                : tab.tr("no_active", "No active package")
        }

        Flow {
            Layout.fillWidth: true
            spacing: Scaler.s(8)

            ActionButton {
                objectName: "themessImport"
                text: tab.tr("import", "Import Folder")
                highlighted: true
                enabled: !Themess.busy
                onClicked: picker.open()
            }
            ActionButton {
                text: tab.tr("refresh", "Refresh")
                enabled: !Themess.busy
                onClicked: tab.refresh()
            }
            ActionButton {
                text: tab.tr("restore", "Restore Previous")
                enabled: !Themess.busy && Themess.canRestore
                onClicked: Themess.run("restore", tab.outputName)
            }
            ActionButton {
                text: tab.tr("restore_original", "Restore Original")
                enabled: !Themess.busy && Themess.canRestoreOriginal
                onClicked: Themess.run("restore-original", tab.outputName)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: Themess.busy || !!Themess.message
            BusyIndicator {
                Layout.preferredWidth: Scaler.s(25)
                Layout.preferredHeight: Scaler.s(25)
                running: Themess.busy
                visible: running
            }
            Copy {
                Layout.fillWidth: true
                text: Themess.busy ? tab.tr("progress." + Themess.operation, "Working…") : Themess.message
            }
        }

        Repeater {
            model: Themess.errors
            delegate: Copy {
                required property string modelData
                Layout.fillWidth: true
                color: ThemeBackend.red
                text: modelData
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !tab.showDetails

            TextField {
                id: query
                objectName: "themessSearch"
                Layout.fillWidth: true
                placeholderText: tab.tr("search", "Search packages")
                Accessible.name: placeholderText
                palette.base: ThemeBackend.surface0
                palette.text: ThemeBackend.text
                font.family: ThemeBackend.fontFamily
            }
            ComboBox {
                id: filter
                Accessible.name: tab.tr("filter", "Filter packages")
                model: [tab.tr("all", "All packages"), tab.tr("can_apply", "Can be applied"),
                        tab.tr("needs_attention", "Needs attention"), tab.tr("active", "Active package")]
                palette.button: ThemeBackend.surface0
                palette.buttonText: ThemeBackend.text
            }
        }

        ScrollView {
            id: galleryScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !tab.showDetails
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: galleryScroll.availableWidth

                GridLayout {
                    id: gallery
                    Layout.fillWidth: true
                    columns: Math.max(1, Math.min(3, Math.floor((width + columnSpacing) / Scaler.s(280))))
                    columnSpacing: Scaler.s(12)
                    rowSpacing: Scaler.s(12)

                    Repeater {
                        id: cards
                        objectName: "themessCards"
                        model: Themess.packages.filter(item => {
                            const needle = query.text.trim().toLowerCase();
                            if (needle && ![item.name, item.author, item.description, item.folder]
                                    .some(value => value.toLowerCase().includes(needle))) return false;
                            if (filter.currentIndex === 1) return !item.errors.length;
                            if (filter.currentIndex === 2) return item.errors.length || item.warnings.length;
                            if (filter.currentIndex === 3) return Themess.active?.folder === item.folder;
                            return true;
                        })

                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            readonly property bool active: Themess.active?.folder === modelData.folder
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredWidth: (gallery.width - (gallery.columns - 1) * gallery.columnSpacing) / gallery.columns
                            Layout.alignment: Qt.AlignTop
                            implicitHeight: content.implicitHeight + Scaler.s(24)
                            radius: ThemeBackend.borderRadius
                            color: cardGlass.active ? "transparent" : ThemeBackend.surface0
                            border.color: active ? ThemeBackend.mauve : "transparent"
                            border.width: 1

                            GlassFill {
                                id: cardGlass
                                anchors.fill: parent
                                radius: card.radius
                                tintColor: ThemeBackend.surface0
                                tintAmount: 0.3
                            }

                            ColumnLayout {
                                id: content
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Scaler.s(12)
                                spacing: Scaler.s(7)

                                ThemessPreview {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: implicitHeight
                                    packageData: card.modelData
                                }
                                Copy {
                                    Layout.fillWidth: true
                                    text: card.modelData.name
                                    font.bold: true
                                    font.pixelSize: Scaler.s(17)
                                }
                                Copy {
                                    Layout.fillWidth: true
                                    color: ThemeBackend.subtext1
                                    text: card.modelData.author || tab.tr("unknown_author", "Author unspecified")
                                }
                                Copy {
                                    Layout.fillWidth: true
                                    visible: !!text
                                    text: card.modelData.description
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                }
                                Copy {
                                    Layout.fillWidth: true
                                    color: card.modelData.errors.length ? ThemeBackend.red
                                        : (card.modelData.warnings.length ? ThemeBackend.yellow : ThemeBackend.mauve)
                                    text: tab.tr("components", "Components") + " · " + card.modelData.components.length
                                        + "   |   " + tab.compatibility(card.modelData)
                                        + (card.active ? "   |   " + tab.tr("active", "Active package") : "")
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: Scaler.s(6)

                                    ActionButton {
                                        text: tab.tr("view", "View Components")
                                        enabled: !Themess.busy
                                        onClicked: tab.openDetails(card.modelData, false)
                                    }
                                    ActionButton {
                                        text: tab.tr("preview", "Preview")
                                        enabled: !Themess.busy && card.modelData.available
                                        onClicked: tab.openDetails(card.modelData, true)
                                    }
                                    ActionButton {
                                        text: tab.tr("apply", "Apply")
                                        highlighted: true
                                        enabled: !Themess.busy && !card.modelData.errors.length
                                        onClicked: {
                                            tab.openDetails(card.modelData, false);
                                            Themess.requestApply(card.modelData, tab.outputName);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Copy {
                    Layout.fillWidth: true
                    visible: cards.count === 0 && !Themess.busy
                    text: Themess.packages.length ? tab.tr("no_matches", "No matching packages")
                        : tab.tr("empty", "Import a package folder to add it to your library.")
                }
            }
        }

        ScrollView {
            id: detailsScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: tab.showDetails
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: detailsScroll.availableWidth
                spacing: Scaler.s(10)

                ActionButton {
                    text: tab.tr("back", "Back to Library")
                    onClicked: tab.showDetails = false
                }

                ColumnLayout {
                    id: detail
                    Layout.fillWidth: true
                    visible: !!tab.inspection
                    readonly property var details: tab.inspection || {}
                    spacing: Scaler.s(8)

                    Copy {
                        Layout.fillWidth: true
                        text: detail.details.name || ""
                        font.bold: true
                        font.pixelSize: Scaler.s(20)
                    }
                    Copy {
                        Layout.fillWidth: true
                        color: ThemeBackend.subtext1
                        text: detail.details.folder || ""
                        wrapMode: Text.WrapAnywhere
                    }
                    Copy {
                        Layout.fillWidth: true
                        text: detail.details.description || ""
                        visible: !!text
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Scaler.s(6)
                        ActionButton {
                            text: tab.tr("preview", "Preview")
                            enabled: !Themess.busy && !!tab.selected?.available
                            onClicked: tab.openDetails(tab.selected, true)
                        }
                        ActionButton {
                            text: tab.tr("apply", "Apply")
                            highlighted: true
                            enabled: !Themess.busy && !!tab.inspection && !tab.inspection.errors.length
                            onClicked: Themess.requestApply(tab.inspection, tab.outputName)
                        }
                        ActionButton {
                            text: tab.tr("open", "Open Theme Folder")
                            enabled: !Themess.busy && !!tab.selected?.available
                            onClicked: {
                                if (!Qt.openUrlExternally(tab.selected.url))
                                    Themess.errors = [tab.tr("open_failed", "Could not open the package folder.")];
                            }
                        }
                        ActionButton {
                            text: tab.tr("remove", "Remove From Library")
                            enabled: !Themess.busy && !!tab.selected
                            onClicked: {
                                if (Themess.run("remove", tab.outputName, tab.selected.folder))
                                    tab.showDetails = false;
                            }
                        }
                    }

                    Copy {
                        Layout.fillWidth: true
                        visible: !!detail.details.preview
                        text: tab.tr("preview_caption", "Desktop preview · approximate layout")
                        font.bold: true
                    }
                    ThemessPreview {
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        Layout.maximumWidth: Scaler.s(760)
                        visible: !!detail.details.preview
                        packageData: detail.details
                    }
                    Flow {
                        Layout.fillWidth: true
                        visible: !!detail.details.preview
                        spacing: Scaler.s(6)
                        Repeater {
                            model: Object.entries(detail.details.appearance?.theme?.colors || {})
                            delegate: Rectangle {
                                required property var modelData
                                width: Scaler.s(28)
                                height: Scaler.s(23)
                                color: modelData[1]
                                radius: Scaler.s(4)
                                border.color: ThemeBackend.surface1
                                border.width: 1
                                ToolTip.visible: swatchHover.hovered
                                ToolTip.text: modelData.join(" · ")
                                HoverHandler { id: swatchHover }
                            }
                        }
                    }

                    Repeater {
                        model: (detail.details.errors || []).concat(detail.details.warnings || [])
                        delegate: Copy {
                            required property string modelData
                            required property int index
                            Layout.fillWidth: true
                            color: index < (detail.details.errors || []).length ? ThemeBackend.red : ThemeBackend.yellow
                            visible: !Themess.errors.includes(modelData)
                            text: modelData
                        }
                    }

                    Copy {
                        text: tab.tr("components", "Components")
                        font.bold: true
                    }
                    Repeater {
                        model: detail.details.components || []
                        delegate: ColumnLayout {
                            id: entry
                            required property var modelData
                            readonly property string summary: tab.componentSummary(detail.details, modelData.kind)
                            Layout.fillWidth: true
                            spacing: Scaler.s(2)
                            Copy {
                                Layout.fillWidth: true
                                text: tab.tr("component." + entry.modelData.kind, entry.modelData.kind)
                                    + " · " + entry.modelData.file
                            }
                            Copy {
                                Layout.fillWidth: true
                                visible: !!text
                                color: ThemeBackend.subtext1
                                text: entry.summary
                            }
                        }
                    }
                    Copy {
                        Layout.fillWidth: true
                        color: ThemeBackend.subtext1
                        visible: !!detail.details.preview && !!detail.details.widgetScreen
                        text: tab.tr("widget_output", "Widget output") + " · " + (detail.details.widgetScreen || "")
                    }
                    Copy {
                        Layout.fillWidth: true
                        color: ThemeBackend.subtext1
                        visible: !!detail.details.preview && (detail.details.wallpaperScreens || []).length > 0
                        text: tab.tr("wallpaper_outputs", "Wallpaper outputs") + " · "
                            + (detail.details.wallpaperScreens || []).join(", ")
                    }
                    Repeater {
                        model: detail.details.preview ? detail.details.settings || [] : []
                        delegate: Copy {
                            required property var modelData
                            Layout.fillWidth: true
                            color: ThemeBackend.subtext1
                            wrapMode: Text.WrapAnywhere
                            text: modelData.setting + "   " + JSON.stringify(modelData.before)
                                + " → " + JSON.stringify(modelData.after)
                        }
                    }
                }
            }
        }
    }
}
