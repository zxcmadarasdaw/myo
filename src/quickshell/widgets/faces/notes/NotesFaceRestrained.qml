import QtQuick
import QtQuick.Layouts
import "../../../"
import "../common"

// Notes, Restrained: a small-caps heading, then the notes as plain lines
// separated by 1 px rules: title, one muted line of text, the age.
NotesStyledBase {
    id: root
    clip: true

    readonly property FaceTone tone: FaceTone {}
    readonly property real pad: Math.max(Scaler.s(10), Math.min(width, height) * 0.06)

    MinimalAppear { target: root }

    MinimalCard { anchors.fill: parent }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Scaler.s(6)

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: I18n.t("widgets.types.notes", "Notes").toUpperCase()
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(10)
                font.letterSpacing: Scaler.s(1.5)
                color: root.tone.muted
            }
            Text {
                text: root.sortedNotes.length > 0 ? String(root.sortedNotes.length) : ""
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(10)
                color: root.tone.faint
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.tone.hairline }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 0
            boundsBehavior: Flickable.StopAtBounds
            model: root.sortedNotes

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: list.width
                height: col.implicitHeight + Scaler.s(12)

                Rectangle {
                    anchors.fill: parent
                    color: Qt.alpha(ThemeBackend.text, rowArea.containsMouse ? 0.05 : 0)
                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                ColumnLayout {
                    id: col
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Scaler.s(1)
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: (row.modelData.pinned ? "· " : "") + (row.modelData.title || I18n.t("widgets.notes.untitled", "Untitled"))
                            elide: Text.ElideRight
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: Scaler.s(12)
                            color: root.tone.ink
                        }
                        Text {
                            text: row.modelData.updatedAt ? root.relativeTime(row.modelData.updatedAt) : ""
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: Scaler.s(9)
                            color: root.tone.faint
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.snippet(row.modelData)
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: root.tone.muted
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: root.tone.hairline
                    visible: row.index < list.count - 1
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openNotes()
                }
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                text: I18n.t("widgets.notes.empty", "No notes yet")
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(11)
                color: root.tone.faint
            }
        }
    }
}
