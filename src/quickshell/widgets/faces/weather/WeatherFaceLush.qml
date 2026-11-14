import QtQuick
import QtQuick.Layouts
import "../../../reusables"
import "../../../"
import "../common"

// Weather, Lush: the card is tinted with the colour of the current weather,
// the condition icon glows, and the temperature is set as a display figure.
Item {
    id: root
    anchors.fill: parent

    property bool previewMode: false
    property real minWidth: 150
    property real minHeight: 90
    property real maxWidth: 800
    property real maxHeight: 600
    property real minAspect: 0.8
    property real maxAspect: 4.0
    property bool isRound: false

    readonly property FaceTone tone: FaceTone {}
    readonly property bool isLoading: Weather.isLoading || !Weather.isReady
    readonly property color weatherColor: (Weather.currentHex && Weather.currentHex.length === 7) ? Weather.currentHex : tone.accent
    readonly property string tempText: Weather.currentTemp !== "" ? Math.round(parseFloat(Weather.currentTemp)) + "°" : "--°"
    readonly property string descText: (Weather.data && Weather.data.forecast && Weather.data.forecast[0] && Weather.data.forecast[0].desc)
        ? Weather.data.forecast[0].desc : (Weather.data && Weather.data.desc ? Weather.data.desc : "")
    readonly property string cityText: Location.city && Location.city !== "" ? Location.city : (Weather.data && Weather.data.city ? Weather.data.city : "")
    readonly property bool wide: width > height * 1.25
    readonly property real pad: Math.max(Scaler.s(14), Math.min(width, height) * 0.13)

    LushAppear { target: root }

    LushCard {
        anchors.fill: parent
        accent: root.weatherColor
        accent2: root.tone.accent
        intensity: 0.8
    }

    LoaderIcon {
        anchors.centerIn: parent
        width: Math.max(20, Math.min(44, Math.min(root.width, root.height) * 0.3))
        height: width
        accentColor: root.weatherColor
        running: root.isLoading
        visible: root.isLoading
    }

    GridLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        columns: root.wide ? 2 : 1
        columnSpacing: root.pad * 0.6
        rowSpacing: Scaler.s(2)
        visible: !root.isLoading

        LushGlowText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            Layout.preferredHeight: 1     // size from the layout, not from the glyph (no binding loop)
            text: Weather.currentIcon
            font.pixelSize: Math.max(8, Math.min(height * 0.9, width * 0.9))
            fontSizeMode: Text.Fit
            minimumPixelSize: 8
            color: root.weatherColor
            glowColor: root.tone.isLight ? root.tone.glow : root.weatherColor
            glowAmount: 1.0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1.2
            spacing: 0

            LushGlowText {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 1
                text: root.tempText
                font.weight: Font.DemiBold
                font.pixelSize: height
                fontSizeMode: Text.Fit
                minimumPixelSize: 12
                horizontalAlignment: root.wide ? Text.AlignLeft : Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                glowAmount: 0.6
            }
            Text {
                Layout.fillWidth: true
                visible: root.descText !== "" && root.height >= Scaler.s(110)
                text: root.descText
                elide: Text.ElideRight
                horizontalAlignment: root.wide ? Text.AlignLeft : Text.AlignHCenter
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(Scaler.s(10), Math.min(Scaler.s(14), root.height * 0.09))
                font.italic: true
                color: root.tone.ink
            }
            Text {
                Layout.fillWidth: true
                visible: root.cityText !== "" && root.height >= Scaler.s(130)
                text: root.cityText
                elide: Text.ElideRight
                horizontalAlignment: root.wide ? Text.AlignLeft : Text.AlignHCenter
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(Scaler.s(8), Math.min(Scaler.s(11), root.height * 0.07))
                font.letterSpacing: Scaler.s(2)
                font.capitalization: Font.AllUppercase
                color: root.tone.muted
            }
        }
    }
}
