import QtQuick
import QtQuick.Layouts
import "../../../"
import "../common"

// Notes, Atelier: the same notes as the quick-actions Notes (NotesStyledBase), listed
// in the type and frame of the chosen look. Click: open Notes.
NotesStyledBase {
    id: root
    clip: true

    property string faceStyle: "editorial"
    AtelierKit { id: kit; style: root.faceStyle }
    AtelierAppear { target: root; kit: kit }

    readonly property string look: kit.styleId

    AtelierCard {
        id: card
        kit: kit
        title: I18n.t("widgets.types.notes", "Notes")
        detail: root.sortedNotes.length > 0 ? String(root.sortedNotes.length) : ""
        showHeader: kit.hasHeader
    }

    ListView {
        id: list
        x: card.contentX
        y: card.contentY
        width: card.contentWidth
        height: card.contentHeight
        clip: true
        spacing: root.look === "retro" ? Scaler.s(3) : 0
        boundsBehavior: Flickable.StopAtBounds
        model: root.sortedNotes

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            width: list.width
            height: col.implicitHeight + Scaler.s(root.look === "compact" ? 6 : 12)

            Rectangle {
                anchors.fill: parent
                radius: root.look === "retro" || root.look === "technical" ? 0 : Scaler.s(4)
                color: Qt.alpha(ThemeBackend.text, rowArea.containsMouse ? 0.06 : root.look === "retro" ? 0.03 : 0)
                border.width: root.look === "retro" ? 1 : 0
                border.color: kit.hair
            }

            ColumnLayout {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: root.look === "retro" ? Scaler.s(6) : 0
                anchors.rightMargin: root.look === "retro" ? Scaler.s(6) : 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: Scaler.s(1)
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: (row.modelData.pinned ? (root.look === "technical" ? "* " : "· ") : root.look === "technical" ? "- " : "")
                              + (row.modelData.title || I18n.t("widgets.notes.untitled", "Untitled"))
                        elide: Text.ElideRight
                        font.family: root.look === "elegant" || root.look === "editorial" ? kit.serif
                                     : root.look === "technical" || root.look === "retro" ? kit.mono : kit.sans
                        font.weight: root.look === "editorial" ? Font.DemiBold : Font.Normal
                        font.pixelSize: Scaler.s(root.look === "editorial" ? 14 : 12)
                        color: kit.ink
                    }
                    Text {
                        text: row.modelData.updatedAt ? root.relativeTime(row.modelData.updatedAt) : ""
                        font.family: kit.labelFamily
                        font.pixelSize: Scaler.s(9)
                        color: kit.faint
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== "" && root.look !== "compact"
                    text: root.snippet(row.modelData)
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: root.look === "elegant" ? kit.serif : kit.sans
                    font.italic: root.look === "elegant"
                    font.pixelSize: Scaler.s(10)
                    color: kit.muted
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: kit.hair
                visible: root.look !== "retro" && row.index < list.count - 1
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
            font.family: kit.labelFamily
            font.pixelSize: Scaler.s(11)
            color: kit.faint
        }
    }
}
