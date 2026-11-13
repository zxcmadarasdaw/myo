import QtQuick
import QtQuick.Layouts
import "../../../"

// "Cyber Network": dark neon card.
NetworkFaceBase {
    id: root
    minWidth: 220
    minHeight: 120

    readonly property color neonA: "#00f0ff"
    readonly property color neonB: "#ff2bd6"
    readonly property string mono: "JetBrains Mono"

    property real pulse: 0
    SequentialAnimation on pulse {
        running: root.visible
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 1600; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0; duration: 1600; easing.type: Easing.InOutSine }
    }

    Rectangle {
        anchors.fill: parent
        radius: Scaler.s(6)
        color: Qt.rgba(0.02, 0.03, 0.06, Math.max(0.55, ThemeBackend.elementOpacity))
        border.width: 1
        border.color: Qt.rgba(root.neonA.r, root.neonA.g, root.neonA.b, 0.45 + 0.35 * root.pulse)
    }

    // corner brackets
    Repeater {
        model: 4
        Item {
            width: Scaler.s(14); height: Scaler.s(14)
            x: index % 2 === 0 ? Scaler.s(3) : root.width - width - Scaler.s(3)
            y: index < 2 ? Scaler.s(3) : root.height - height - Scaler.s(3)
            Rectangle { width: parent.width; height: 2; color: root.neonB; y: index < 2 ? 0 : parent.height - 2 }
            Rectangle { width: 2; height: parent.height; color: root.neonB; x: index % 2 === 0 ? 0 : parent.width - 2 }
        }
    }

    NetGraph {
        anchors.fill: parent
        anchors.topMargin: Scaler.s(44)
        anchors.margins: Scaler.s(8)
        rxData: root.hist.rx
        txData: root.hist.tx
        rxColor: root.neonA
        txColor: root.neonB
        glow: true
        fillOpacity: 0.15
        sampleInterval: root.updateInterval
        visible: root.visible
    }

    ColumnLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Scaler.s(12)
        spacing: 0

        Text {
            Layout.fillWidth: true
            text: "> NET::" + root.ifaceName.toUpperCase() + "  [" + root.typeLabel.toUpperCase() + "]" + (root.latencyText !== "" ? "  PING " + root.latencyText : "")
            elide: Text.ElideRight
            font.family: root.mono
            font.pixelSize: Scaler.s(10)
            color: root.neonA
        }
        RowLayout {
            spacing: Scaler.s(14)
            Text { text: "▼ " + root.rxText; font.family: root.mono; font.pixelSize: Scaler.s(14); font.bold: true; color: root.neonA }
            Text { text: "▲ " + root.txText; font.family: root.mono; font.pixelSize: Scaler.s(14); font.bold: true; color: root.neonB }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.isLive
        onClicked: root.cycleInterface()
    }
}
