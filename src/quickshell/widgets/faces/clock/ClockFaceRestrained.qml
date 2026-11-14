import QtQuick
import QtQuick.Layouts
import "../../../"
import "../common"

// Clock, Restrained: light digits, a 1 px rule and the date in small capitals.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property bool previewMode: false
    property real minWidth: 110
    property real minHeight: 50
    property real maxWidth: 1400
    property real maxHeight: 700
    property real minAspect: 1.1
    property real maxAspect: 6.0
    property bool isRound: false

    readonly property FaceTone tone: FaceTone {}
    readonly property bool showDate: height >= Scaler.s(84)
    readonly property real pad: Math.max(Scaler.s(8), Math.min(width, height) * 0.1)

    MinimalAppear { target: root }

    MinimalCard { anchors.fill: parent }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Math.max(Scaler.s(4), root.height * 0.04)

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: DateTime.hour + "<font color='" + root.tone.faint + "'>:</font>" + DateTime.minute
                  + (DateTime.amPm !== "" ? "<font color='" + root.tone.muted + "'><small> " + DateTime.amPm + "</small></font>" : "")
            textFormat: Text.StyledText
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Light
            font.pixelSize: height
            fontSizeMode: Text.Fit
            minimumPixelSize: 10
            font.letterSpacing: height * 0.02
            color: root.tone.ink
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
        }

        Rectangle {
            visible: root.showDate
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: root.tone.hairline
        }

        Text {
            visible: root.showDate
            Layout.fillWidth: true
            text: (DateTime.dayName + " · " + DateTime.fullDate).toUpperCase()
            elide: Text.ElideRight
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Math.max(Scaler.s(9), Math.min(Scaler.s(13), root.height * 0.09))
            font.letterSpacing: Scaler.s(1.5)
            color: root.tone.muted
        }
    }
}
