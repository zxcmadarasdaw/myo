import QtQuick
import QtQuick.Layouts
import "../../../reusables"
import "../../../"
import "../common"

// Weather, Restrained: a light temperature figure, a 1 px divider and a
// quiet column with the condition and the city.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property bool previewMode: false
    property real minWidth: 110
    property real minHeight: 56
    property real maxWidth: 800
    property real maxHeight: 500
    property real minAspect: 0.9
    property real maxAspect: 5.0
    property bool isRound: false

    readonly property FaceTone tone: FaceTone {}
    readonly property bool isLoading: Weather.isLoading || !Weather.isReady
    readonly property string tempText: Weather.currentTemp !== "" ? Math.round(parseFloat(Weather.currentTemp)) + "°" : "--°"
    readonly property string descText: (Weather.data && Weather.data.forecast && Weather.data.forecast[0] && Weather.data.forecast[0].desc)
        ? Weather.data.forecast[0].desc : (Weather.data && Weather.data.desc ? Weather.data.desc : "")
    readonly property string cityText: Location.city && Location.city !== "" ? Location.city : (Weather.data && Weather.data.city ? Weather.data.city : "")
    readonly property bool showDetails: width >= Scaler.s(170)
    readonly property real pad: Math.max(Scaler.s(8), Math.min(width, height) * 0.12)

    MinimalAppear { target: root }

    MinimalCard { anchors.fill: parent }

    Text {
        anchors.centerIn: parent
        visible: root.isLoading
        text: "…"
        font.family: ThemeBackend.fontFamily
        font.pixelSize: Scaler.s(18)
        color: root.tone.faint
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: root.pad
        visible: !root.isLoading

        Text {
            Layout.fillHeight: true
            Layout.fillWidth: !root.showDetails
            Layout.preferredWidth: root.showDetails ? root.width * 0.42 : -1
            text: root.tempText
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Light
            font.pixelSize: height
            fontSizeMode: Text.Fit
            minimumPixelSize: 10
            color: root.tone.ink
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: root.showDetails ? Text.AlignLeft : Text.AlignHCenter
        }

        Rectangle {
            visible: root.showDetails
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            Layout.topMargin: root.height * 0.08
            Layout.bottomMargin: root.height * 0.08
            color: root.tone.hairline
        }

        ColumnLayout {
            visible: root.showDetails
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Scaler.s(2)

            Text {
                text: Weather.currentIcon
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(Scaler.s(14), Math.min(Scaler.s(30), root.height * 0.22))
                color: root.tone.quietAccent
            }
            Text {
                Layout.fillWidth: true
                text: root.descText
                elide: Text.ElideRight
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(Scaler.s(10), Math.min(Scaler.s(13), root.height * 0.11))
                color: root.tone.ink
            }
            Text {
                Layout.fillWidth: true
                visible: root.cityText !== "" && root.height >= Scaler.s(80)
                text: root.cityText.toUpperCase()
                elide: Text.ElideRight
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(Scaler.s(8), Math.min(Scaler.s(11), root.height * 0.08))
                font.letterSpacing: Scaler.s(1.5)
                color: root.tone.muted
            }
        }
    }
}
