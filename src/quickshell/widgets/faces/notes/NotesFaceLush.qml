import QtQuick
import QtQuick.Layouts
import "../../../"
import "../common"

// Notes, Lush: a display-set heading on ornamented glass and the notes as
// soft glass slips; pinned notes carry an accent edge.
NotesStyledBase {
    id: root
    minWidth: 240
    minHeight: 180

    readonly property FaceTone tone: FaceTone {}
    readonly property real pad: Math.max(Scaler.s(14), Math.min(width, height) * 0.07)

    LushAppear { target: root }

    LushCard { anchors.fill: parent; intensity: 0.6 }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Scaler.s(8)

        RowLayout {
            Layout.fillWidth: true
            spacing: Scaler.s(8)
            LushGlowText {
                Layout.fillWidth: true
                text: I18n.t("widgets.types.notes", "Notes")
                font.pixelSize: Scaler.s(18)
                font.weight: Font.DemiBold
                font.italic: true
                glowAmount: 0.7
            }
            FaceButton {
                lush: true
                text: "+"
                iconFont: ThemeBackend.fontFamily
                implicitWidth: Scaler.s(28); implicitHeight: Scaler.s(26)
                accessibleName: I18n.t("widgets.notes.open", "Open notes")
                enabled: !root.previewMode && root.quickactionsAvailable
                onClicked: root.openNotes()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.alpha(root.tone.accent, 0.7) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Scaler.s(6)
            boundsBehavior: Flickable.StopAtBounds
            model: root.sortedNotes

            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic } }
            displaced: Transition { NumberAnimation { properties: "y"; duration: 320; easing.type: Easing.OutQuint } }

            delegate: Rectangle {
                id: slip
                required property var modelData
                width: list.width
                height: col.implicitHeight + Scaler.s(16)
                radius: Scaler.s(10)
                color: Qt.alpha(ThemeBackend.text, slipArea.containsMouse ? 0.1 : 0.05)
                border.width: 1
                border.color: Qt.alpha(root.tone.sheen, root.tone.isLight ? 0.5 : 0.08)
                Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

                Rectangle {
                    visible: !!slip.modelData.pinned
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: Scaler.s(6)
                    width: Scaler.s(2)
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: root.tone.accent }
                        GradientStop { position: 1.0; color: root.tone.accent2 }
                    }
                }

                ColumnLayout {
                    id: col
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Scaler.s(14)
                    anchors.rightMargin: Scaler.s(10)
                    spacing: Scaler.s(2)
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: slip.modelData.title || I18n.t("widgets.notes.untitled", "Untitled")
                            elide: Text.ElideRight
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: Scaler.s(13)
                            font.weight: Font.DemiBold
                            color: root.tone.ink
                        }
                        Text {
                            text: slip.modelData.updatedAt ? root.relativeTime(slip.modelData.updatedAt) : ""
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: Scaler.s(9)
                            font.italic: true
                            color: root.tone.faint
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.snippet(slip.modelData)
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: root.tone.muted
                    }
                }

                MouseArea {
                    id: slipArea
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
                font.pixelSize: Scaler.s(12)
                font.italic: true
                color: root.tone.faint
            }
        }
    }
}
