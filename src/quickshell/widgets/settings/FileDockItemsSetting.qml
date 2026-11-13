import QtQuick
import QtQuick.Controls
import "../../"
import "../../reusables"
import "../faces/filedock/FileDockIcons.js" as Icons

// Widget editor: manage the shortcuts of a File Dock.
// "+ File" / "+ Folder" open Serpantinum's own file picker; "Items" lists the
// shortcuts with move up / down / remove. Remove drops the shortcut only.
Item {
    id: settingRoot
    property var typeData: null
    property var settingData: null
    property var redactor: null
    property var widget: null
    property var widgetData: null
    property var item: null

    readonly property var face: settingRoot.widget || settingRoot.item || null
    readonly property int itemCount: face && face.count !== undefined ? face.count : 0

    function push() {
        if (face && settingRoot.redactor) settingRoot.redactor.setWidgetProperty("itemsJson", face.itemsJson);
    }

    function add(path, isDir) {
        if (!face || typeof face.addPath !== "function") return;
        if (face.addPath(path, isDir)) push();
    }

    implicitWidth: row.implicitWidth
    implicitHeight: Scaler.s(34)

    component Pill: Rectangle {
        id: pill
        property string label: ""
        property string glyph: ""
        signal activated()
        implicitWidth: pillRow.implicitWidth + Scaler.s(20)
        implicitHeight: Scaler.s(34)
        radius: ThemeBackend.borderRadius
        color: pillArea.containsMouse ? ThemeBackend.surface1 : ThemeBackend.surface0
        Behavior on color { ColorAnimation { duration: 150 } }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: Scaler.s(6)
            Text { text: pill.glyph; font.family: ThemeBackend.iconFont; font.pixelSize: Scaler.s(13); color: ThemeBackend.mauve; anchors.verticalCenter: parent.verticalCenter }
            Text { text: pill.label; font.family: ThemeBackend.fontFamily; font.pixelSize: Scaler.s(11); font.bold: true; color: ThemeBackend.text; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: pillArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pill.activated() }
    }

    Row {
        id: row
        spacing: Scaler.s(6)
        Pill { glyph: "󰈔"; label: I18n.t("widgets.filedock.addFile", "File"); onActivated: { picker.folderMode = false; picker.openWithOptionalPath(""); } }
        Pill { glyph: "󰉗"; label: I18n.t("widgets.filedock.addFolder", "Folder"); onActivated: { picker.folderMode = true; picker.openWithOptionalPath(""); } }
        Pill { glyph: "󰕲"; label: I18n.t("widgets.filedock.items", "Items") + " (" + settingRoot.itemCount + ")"; onActivated: listPopup.open() }
    }

    FilePicker {
        id: picker
        rootObj: settingRoot.redactor
        titleText: folderMode ? I18n.t("widgets.filedock.pickFolder", "Open the folder to pin, then press Pin") : I18n.t("widgets.filedock.pickFile", "Pick a file to pin")
        doneButtonText: I18n.t("widgets.filedock.pin", "Pin")
        onFileSelected: function(filePath, fileName) {
            settingRoot.add(String(filePath).replace(/^file:\/\//, ""), picker.folderMode);
        }
    }

    Popup {
        id: listPopup
        parent: settingRoot.redactor ? (settingRoot.redactor.contentItem || settingRoot.redactor) : settingRoot
        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0
        width: Scaler.s(460)
        height: Math.min(Scaler.s(480), Scaler.s(70) + Math.max(1, settingRoot.itemCount) * Scaler.s(40))
        modal: true
        dim: true
        padding: Scaler.s(14)
        z: 300000
        background: Rectangle { radius: ThemeBackend.borderRadius; color: ThemeBackend.base; border.width: 1; border.color: ThemeBackend.surface1 }

        Column {
            anchors.fill: parent
            spacing: Scaler.s(8)

            Text {
                text: I18n.t("widgets.filedock.manage", "Shortcuts (removing one never touches the file)")
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(12)
                font.bold: true
                color: ThemeBackend.text
            }

            ListView {
                width: parent.width
                height: parent.height - Scaler.s(30)
                clip: true
                spacing: Scaler.s(4)
                model: settingRoot.face ? settingRoot.face.model : null
                move: Transition { NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic } }

                delegate: Rectangle {
                    required property int index
                    required property string path
                    required property string name
                    required property bool dir
                    width: ListView.view.width
                    height: Scaler.s(36)
                    radius: Scaler.s(6)
                    color: ThemeBackend.surface0

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Scaler.s(10)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Scaler.s(8)
                        width: parent.width - Scaler.s(120)
                        Text { text: Icons.icon(path, dir, ""); font.family: ThemeBackend.iconFont; font.pixelSize: Scaler.s(15); color: ThemeBackend.blue; anchors.verticalCenter: parent.verticalCenter }
                        Column {
                            width: parent.width - Scaler.s(30)
                            anchors.verticalCenter: parent.verticalCenter
                            Text { width: parent.width; text: name; elide: Text.ElideRight; font.family: ThemeBackend.fontFamily; font.pixelSize: Scaler.s(11); font.bold: true; color: ThemeBackend.text }
                            Text { width: parent.width; text: path; elide: Text.ElideMiddle; font.family: ThemeBackend.fontFamily; font.pixelSize: Scaler.s(9); color: ThemeBackend.subtext0 }
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: Scaler.s(6)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Scaler.s(2)
                        Repeater {
                            model: [
                                { g: "󰁝", act: "up" },
                                { g: "󰁅", act: "down" },
                                { g: "󰅖", act: "remove" }
                            ]
                            Text {
                                width: Scaler.s(28); height: Scaler.s(28)
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: modelData.g
                                font.family: ThemeBackend.iconFont
                                font.pixelSize: Scaler.s(15)
                                color: btn.containsMouse ? (modelData.act === "remove" ? ThemeBackend.red : ThemeBackend.mauve) : ThemeBackend.subtext0
                                MouseArea {
                                    id: btn
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        let f = settingRoot.face;
                                        if (!f) return;
                                        if (modelData.act === "up") f.moveItem(index, index - 1);
                                        else if (modelData.act === "down") f.moveItem(index, index + 1);
                                        else f.removeAt(index);
                                        settingRoot.push();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
