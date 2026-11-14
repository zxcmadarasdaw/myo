import QtQuick
import QtQuick.Layouts
import "../../../"
import "../../../notifications/weather"
import "../common"

// Weather, Atelier. The scene is the existing animated WeatherIllustration (the same
// art as the weather notifications), driven by the real WMO code of Weather.qml; it only
// moves with Atelier motion "full" and while the widget is visible.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property bool previewMode: false
    property string faceStyle: "matte"
    property real minWidth: 130
    property real minHeight: 56
    property real maxWidth: 900
    property real maxHeight: 600
    property real minAspect: 0.8
    property real maxAspect: 7.0
    property bool isRound: false

    AtelierKit { id: kit; style: root.faceStyle }
    AtelierAppear { target: root; kit: kit }

    readonly property string look: kit.styleId
    readonly property bool compact: look === "compact" || height < Scaler.s(90)
    readonly property bool isLoading: Weather.isLoading || !Weather.isReady
    readonly property string tempText: Weather.currentTemp !== "" ? Math.round(parseFloat(Weather.currentTemp)) + "°" : "--°"
    readonly property string descText: (Weather.data && Weather.data.forecast && Weather.data.forecast[0] && Weather.data.forecast[0].desc)
        ? Weather.data.forecast[0].desc : (Weather.data && Weather.data.desc ? Weather.data.desc : "")
    readonly property string cityText: Location.city && Location.city !== "" ? Location.city : (Weather.data && Weather.data.city ? Weather.data.city : "")
    readonly property string sceneKind: Weather.currentCode >= 0 ? "wmo_" + Weather.currentCode + (Weather.currentIsDay === 0 ? "_n" : "") : ""
    readonly property bool framedScene: look === "retro" || look === "technical"

    AtelierCard {
        id: card
        kit: kit
        title: root.cityText !== "" ? root.cityText : I18n.t("widgets.types.weather", "Weather")
        detail: root.framedScene && Weather.currentCode >= 0 ? "WMO " + Weather.currentCode : ""
        showHeader: kit.hasHeader && !root.compact
    }

    Text {
        anchors.centerIn: parent
        visible: root.isLoading
        text: "…"
        font.pixelSize: Scaler.s(18)
        color: kit.faint
    }

    RowLayout {
        visible: !root.isLoading
        x: card.contentX
        y: card.contentY
        width: card.contentWidth
        height: card.contentHeight
        spacing: Scaler.s(root.compact ? 8 : 14)

        // the scene: framed like a small screen in Retro / Technical, free elsewhere
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: Math.min(card.contentHeight * (root.compact ? 1 : 1.1), root.width * 0.42)
            color: root.framedScene ? Qt.alpha(ThemeBackend.crust, 0.8) : "transparent"
            border.width: root.framedScene ? 1 : 0
            border.color: Qt.alpha(kit.accent, 0.45)
            radius: root.look === "retro" ? 0 : Math.min(kit.radius, Scaler.s(8))
            clip: true

            WeatherIllustration {
                anchors.fill: parent
                anchors.margins: parent.border.width
                visible: root.sceneKind !== ""
                kind: root.sceneKind
                animate: kit.loops && root.visible && !root.previewMode
                backdrop: root.look === "premium" || root.framedScene
                radius: parent.radius
            }
            Text {
                anchors.centerIn: parent
                visible: root.sceneKind === ""
                text: Weather.currentIcon
                font.pixelSize: parent.height * 0.5
                color: kit.accent
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Scaler.s(1)

            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: root.tempText
                font.family: kit.displayFamily
                font.weight: kit.displayWeight
                font.pixelSize: height
                fontSizeMode: Text.Fit
                minimumPixelSize: 10
                color: kit.ink
                verticalAlignment: Text.AlignVCenter
            }
            Text {
                Layout.fillWidth: true
                text: root.framedScene ? root.descText.toUpperCase() : root.descText
                visible: text !== ""
                elide: Text.ElideRight
                font.family: root.look === "elegant" ? kit.serif : kit.labelFamily
                font.italic: root.look === "elegant"
                font.pixelSize: Math.max(Scaler.s(10), Math.min(Scaler.s(14), root.height * 0.1))
                color: root.look === "editorial" ? kit.accent : kit.muted
            }
            Text {
                Layout.fillWidth: true
                visible: root.compact && root.cityText !== "" && root.height >= Scaler.s(64)
                text: kit.label(root.cityText)
                elide: Text.ElideRight
                font.family: kit.labelFamily
                font.pixelSize: Scaler.s(9)
                font.letterSpacing: kit.tracking
                color: kit.faint
            }
        }
    }
}
