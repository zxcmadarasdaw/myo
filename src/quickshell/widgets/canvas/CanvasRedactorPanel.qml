import QtQuick
import QtQuick.Layouts
import "../../"
import "../../reusables"
import "CanvasMath.js" as CM

// Infinite canvas controls inside the widget redactor: camera buttons, minimap,
// widget search, selection / group actions and saved compositions.
Item {
    id: panel

    // The redactor's `redactorMode` item.
    required property var redactor
    required property string monitorName

    property bool expanded: true
    property bool namingComposition: false
    property string query: ""
    property string notice: ""

    readonly property var cam: redactor ? redactor.cam : null
    readonly property bool canvasOn: redactor ? redactor.canvasOn : false
    readonly property var selection: redactor ? redactor.selectionIdList : []
    readonly property bool inputActive: searchInput.hasFocus || nameInput.hasFocus
    readonly property var results: panel.query.trim() === ""
        ? []
        : CM.searchWidgets(redactor.canvasWidgets, panel.query, CanvasState.typeNames()).slice(0, 6)

    property Item glassBackdropItem: backdrop

    width: s(272)
    height: card.height

    function s(val) { return Scaler.s(val); }
    function icon(code) { return String.fromCodePoint(code); }

    // Escape handling: returns true when the panel consumed it.
    function dismiss() {
        if (panel.namingComposition) {
            panel.namingComposition = false;
            return true;
        }
        if (searchInput.hasFocus || panel.query !== "") {
            panel.query = "";
            searchInput.clear();
            searchInput.releaseFocus();
            return true;
        }
        return false;
    }

    function focusSearch() {
        panel.expanded = true;
        searchInput.forceInputFocus();
    }

    function startNaming() {
        panel.expanded = true;
        panel.namingComposition = true;
        nameInput.clear();
        nameInput.forceInputFocus();
    }

    function commitComposition() {
        let name = nameInput.text.trim();
        if (name === "") {
            nameInput.triggerShake();
            return;
        }
        let id = panel.redactor.saveSelectionAsComposition(name);
        if (id === "") {
            panel.notice = CanvasState.compositionsReadOnly
                ? I18n.t("widgets.canvas.compositions_readonly", "Compositions were saved by a newer version and cannot be changed")
                : I18n.t("widgets.canvas.composition_failed", "Nothing to save");
            noticeTimer.restart();
            return;
        }
        panel.namingComposition = false;
        nameInput.releaseFocus();
    }

    Timer {
        id: noticeTimer
        interval: 3500
        onTriggered: panel.notice = ""
    }

    WallpaperBlur {
        id: backdrop
        standalone: true
        opacity: 0
        anchors.fill: card
        radius: card.radius
    }

    Rectangle {
        id: card
        width: parent.width
        height: column.implicitHeight + s(20)
        radius: ThemeBackend.borderRadius
        color: cardGlass.active ? "transparent" : Qt.alpha(ThemeBackend.base, 0.94)
        border.width: cardGlass.active ? 0 : 1
        border.color: Qt.alpha(ThemeBackend.surface1, 0.8)

        GlassFill {
            id: cardGlass
            anchors.fill: parent
            radius: parent.radius
            tintColor: ThemeBackend.base
            tintAmount: 0.4
        }

        // Clicks on the card must not fall through to the canvas below.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onWheel: wheel => wheel.accepted = true
        }

        ColumnLayout {
            id: column
            x: s(10)
            y: s(10)
            width: parent.width - s(20)
            spacing: s(8)

            RowLayout {
                Layout.fillWidth: true
                spacing: s(4)

                IconButton {
                    size: s(30)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonIcon: panel.icon(0xF02DC)
                    iconFontSize: s(15)
                    visible: panel.canvasOn
                    accentColor: (panel.cam && panel.cam.atHome) ? ThemeBackend.surface0 : ThemeBackend.mauve
                    textColor: (panel.cam && panel.cam.atHome) ? ThemeBackend.text : ThemeBackend.crust
                    onClicked: if (panel.cam) panel.cam.home()
                }

                IconButton {
                    size: s(30)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonIcon: panel.icon(0xF0293)
                    iconFontSize: s(15)
                    visible: panel.canvasOn
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.text
                    onClicked: panel.redactor.fitAll()
                }

                IconButton {
                    size: s(30)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonIcon: panel.icon(0xF0374)
                    iconFontSize: s(15)
                    visible: panel.canvasOn
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.text
                    onClicked: if (panel.cam) panel.cam.zoomBy(1 / panel.cam.cfg.zoomStep)
                }

                Rectangle {
                    Layout.preferredWidth: s(52)
                    Layout.preferredHeight: s(30)
                    visible: panel.canvasOn
                    radius: ThemeBackend.borderRadius
                    color: zoomMa.containsMouse ? ThemeBackend.surface1 : ThemeBackend.surface0

                    Text {
                        anchors.centerIn: parent
                        text: Math.round((panel.cam ? panel.cam.viewZoom : 1) * 100) + "%"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: s(11)
                        font.bold: true
                        color: ThemeBackend.text
                    }

                    MouseArea {
                        id: zoomMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (panel.cam) panel.cam.resetZoom()
                    }
                }

                IconButton {
                    size: s(30)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonIcon: panel.icon(0xF0415)
                    iconFontSize: s(15)
                    visible: panel.canvasOn
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.text
                    onClicked: if (panel.cam) panel.cam.zoomBy(panel.cam.cfg.zoomStep)
                }

                Text {
                    Layout.fillWidth: true
                    visible: !panel.canvasOn
                    text: I18n.t("widgets.canvas.selection_title", "Selection")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: s(12)
                    font.bold: true
                    color: ThemeBackend.text
                    elide: Text.ElideRight
                }

                Item { Layout.fillWidth: true; visible: panel.canvasOn }

                IconButton {
                    size: s(30)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonIcon: panel.icon(panel.expanded ? 0xF0143 : 0xF0140)
                    iconFontSize: s(15)
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.text
                    onClicked: panel.expanded = !panel.expanded
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: s(124)
                visible: panel.expanded && panel.canvasOn
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.crust, 0.45)

                CanvasMinimap {
                    anchors.fill: parent
                    anchors.margins: s(4)
                    widgets: panel.redactor.canvasWidgets
                    camX: panel.cam ? panel.cam.viewX : 0
                    camY: panel.cam ? panel.cam.viewY : 0
                    camZoom: panel.cam ? panel.cam.viewZoom : 1
                    screenW: panel.redactor.width
                    screenH: panel.redactor.height
                    selectedIds: panel.selection
                    onNavigate: (worldX, worldY) => {
                        if (panel.cam) panel.cam.jumpTo(CM.centerOn(worldX, worldY, panel.cam.screenW, panel.cam.screenH, panel.cam.rawZoom));
                    }
                }
            }

            Input {
                id: searchInput
                Layout.fillWidth: true
                Layout.preferredHeight: s(32)
                visible: panel.expanded
                placeholderText: I18n.t("widgets.canvas.search_placeholder", "Find a widget...")
                leadingIcon: panel.icon(0xF0349)
                showClearButton: true
                baseColor: ThemeBackend.surface0
                accentColor: ThemeBackend.mauve
                textColor: ThemeBackend.text
                subTextColor: ThemeBackend.subtext0
                borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                cornerRadius: ThemeBackend.borderRadius
                fontPixelSize: s(12)
                onTextEdited: newText => panel.query = newText
                onCleared: panel.query = ""
                onAccepted: {
                    if (panel.results.length > 0) panel.redactor.focusWidget(panel.results[0].wId);
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: panel.expanded && panel.query.trim() !== ""
                spacing: s(3)

                Repeater {
                    model: panel.results
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: s(28)
                        radius: ThemeBackend.borderRadius
                        color: resultMa.containsMouse ? ThemeBackend.surface1 : Qt.alpha(ThemeBackend.surface0, 0.7)

                        Text {
                            anchors.left: parent.left
                            anchors.right: resultPos.left
                            anchors.leftMargin: s(8)
                            anchors.rightMargin: s(6)
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: s(11)
                            color: ThemeBackend.text
                            elide: Text.ElideRight
                        }

                        Text {
                            id: resultPos
                            anchors.right: parent.right
                            anchors.rightMargin: s(8)
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(modelData.box.x) + ", " + Math.round(modelData.box.y)
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: s(10)
                            color: ThemeBackend.subtext0
                        }

                        MouseArea {
                            id: resultMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.redactor.focusWidget(modelData.wId)
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: panel.results.length === 0
                    text: I18n.t("widgets.redactor.no_results", "Nothing found")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: s(11)
                    color: ThemeBackend.subtext0
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: panel.expanded
                spacing: s(4)

                Text {
                    Layout.fillWidth: true
                    text: panel.selection.length === 0
                        ? I18n.t("widgets.canvas.nothing_selected", "Nothing selected")
                        : I18n.t("widgets.canvas.selected_count", { count: panel.selection.length })
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: s(11)
                    color: panel.selection.length === 0 ? ThemeBackend.subtext0 : ThemeBackend.text
                    elide: Text.ElideRight
                }

                IconButton {
                    size: s(28)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonIcon: panel.icon(0xF0486)
                    iconFontSize: s(14)
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.text
                    onClicked: panel.redactor.selectAll()
                }

                IconButton {
                    size: s(28)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonIcon: panel.icon(0xF02C3)
                    iconFontSize: s(14)
                    enabled: panel.selection.length >= 2
                    opacity: enabled ? 1.0 : 0.4
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.text
                    onClicked: panel.redactor.groupSelection()
                }

                IconButton {
                    size: s(28)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonIcon: panel.icon(0xF0595)
                    iconFontSize: s(14)
                    enabled: panel.redactor.selectionGrouped
                    opacity: enabled ? 1.0 : 0.4
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.text
                    onClicked: panel.redactor.ungroupSelection()
                }

                IconButton {
                    size: s(28)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonIcon: panel.icon(0xF0193)
                    iconFontSize: s(14)
                    enabled: panel.redactor.canvasWidgets.length > 0 && !CanvasState.compositionsReadOnly
                    opacity: enabled ? 1.0 : 0.4
                    accentColor: panel.namingComposition ? ThemeBackend.mauve : ThemeBackend.surface0
                    textColor: panel.namingComposition ? ThemeBackend.crust : ThemeBackend.text
                    onClicked: {
                        if (panel.namingComposition) panel.namingComposition = false;
                        else panel.startNaming();
                    }
                }

                DeleteButton {
                    size: s(28)
                    cornerRadius: ThemeBackend.borderRadius
                    iconFontSize: s(15)
                    enabled: panel.selection.length > 0
                    opacity: enabled ? 1.0 : 0.4
                    onClicked: panel.redactor.removeSelection()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: panel.expanded && panel.namingComposition
                spacing: s(4)

                Input {
                    id: nameInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: s(32)
                    maximumLength: CM.MAX_NAME_LENGTH
                    placeholderText: panel.selection.length > 0
                        ? I18n.t("widgets.canvas.composition_name_selection", "Name for the selection...")
                        : I18n.t("widgets.canvas.composition_name_all", "Name for the whole layout...")
                    baseColor: ThemeBackend.surface0
                    accentColor: ThemeBackend.mauve
                    textColor: ThemeBackend.text
                    subTextColor: ThemeBackend.subtext0
                    borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                    cornerRadius: ThemeBackend.borderRadius
                    fontPixelSize: s(12)
                    onAccepted: panel.commitComposition()
                }

                ClickButton {
                    implicitHeight: s(32)
                    horizontalPadding: s(10)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonText: I18n.t("widgets.canvas.save", "Save")
                    textFontSize: s(11)
                    accentColor: ThemeBackend.mauve
                    textColor: ThemeBackend.crust
                    onClicked: panel.commitComposition()
                }
            }

            Text {
                Layout.fillWidth: true
                visible: panel.expanded && panel.notice !== ""
                text: panel.notice
                wrapMode: Text.WordWrap
                font.family: ThemeBackend.fontFamily
                font.pixelSize: s(10)
                color: ThemeBackend.red
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: panel.expanded && CanvasState.compositions.length > 0
                spacing: s(3)

                Text {
                    Layout.fillWidth: true
                    text: I18n.t("widgets.canvas.compositions", "Compositions")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: s(10)
                    font.bold: true
                    color: ThemeBackend.subtext0
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(compList.implicitHeight, s(138))
                    contentHeight: compList.implicitHeight
                    contentWidth: width
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: compList
                        width: parent.width
                        spacing: s(3)

                        Repeater {
                            model: CanvasState.compositions
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: s(30)
                                radius: ThemeBackend.borderRadius
                                color: Qt.alpha(ThemeBackend.surface0, 0.7)

                                Text {
                                    anchors.left: parent.left
                                    anchors.right: compButtons.left
                                    anchors.leftMargin: s(8)
                                    anchors.rightMargin: s(6)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name + "  (" + modelData.widgets.length + ")"
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: s(11)
                                    color: ThemeBackend.text
                                    elide: Text.ElideRight
                                }

                                Row {
                                    id: compButtons
                                    anchors.right: parent.right
                                    anchors.rightMargin: s(3)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: s(3)

                                    IconButton {
                                        size: s(24)
                                        cornerRadius: ThemeBackend.borderRadius
                                        buttonIcon: panel.icon(0xF0415)
                                        iconFontSize: s(13)
                                        accentColor: ThemeBackend.mauve
                                        textColor: ThemeBackend.crust
                                        onClicked: panel.redactor.insertComposition(modelData.id)
                                    }

                                    DeleteButton {
                                        size: s(24)
                                        cornerRadius: ThemeBackend.borderRadius
                                        iconFontSize: s(13)
                                        visible: !CanvasState.compositionsReadOnly
                                        onClicked: CanvasState.removeComposition(modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: panel.expanded
                text: panel.canvasOn
                    ? I18n.t("widgets.canvas.hint", "Drag empty space: move  ·  Wheel: zoom  ·  Shift+drag: select  ·  Ctrl+G: group")
                    : I18n.t("widgets.canvas.hint_static", "Shift+click or Shift+drag: select several  ·  Ctrl+G: group")
                wrapMode: Text.WordWrap
                font.family: ThemeBackend.fontFamily
                font.pixelSize: s(9)
                color: ThemeBackend.subtext0
            }
        }
    }
}
