import QtQuick
import QtQuick.Layouts
import "../../../reusables"
import "../../../"

// "Live Graph": smooth download / upload history.
NetworkFaceBase {
    id: root
    minWidth: 220
    minHeight: 120

    Rectangle {
        anchors.fill: parent
        radius: ThemeBackend.clampedBorderRadius
        color: Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity)
        clip: true
        WallpaperBlur {
            z: -1
            anchors.fill: parent
            radius: parent.radius
        }
    }

    NetGraph {
        anchors.fill: parent
        anchors.topMargin: Scaler.s(40)
        anchors.bottomMargin: Scaler.s(4)
        anchors.leftMargin: Scaler.s(4)
        anchors.rightMargin: Scaler.s(4)
        rxData: root.hist.rx
        txData: root.hist.tx
        sampleInterval: root.updateInterval
        visible: root.visible
    }

    RowLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Scaler.s(12)
        spacing: Scaler.s(10)

        Text {
            text: root.typeIcon
            font.family: ThemeBackend.iconFont
            font.pixelSize: Scaler.s(15)
            color: ThemeBackend.blue
        }
        Text {
            Layout.fillWidth: true
            text: root.ifaceName + (root.latencyText !== "" ? "  " + root.latencyText : "")
            elide: Text.ElideRight
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(11)
            color: ThemeBackend.subtext0
        }
        Text {
            text: "󰇚 " + root.rxText
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(12)
            font.bold: true
            color: ThemeBackend.blue
        }
        Text {
            text: "󰕒 " + root.txText
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(12)
            font.bold: true
            color: ThemeBackend.mauve
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.isLive
        onClicked: root.cycleInterface()
    }
}
