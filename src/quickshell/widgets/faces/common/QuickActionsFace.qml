import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import "../../../"

Item {
    id: root
    anchors.fill: parent

    property bool previewMode: false
    property string faceStyle: "premium"
    property real minWidth: 250
    property real minHeight: 56

    readonly property var sink: Audio.defaultSink?.audio

    function open(target, page) {
        const args = ["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "toggle", target];
        if (page) args.push(page);
        Quickshell.execDetached(args);
    }

    AtelierKit { id: kit; style: root.faceStyle }
    AtelierAppear { target: root; kit: kit }
    AtelierCard {
        id: card
        kit: kit
        title: qsTr("Quick actions")
        showHeader: root.height >= Scaler.s(76)
    }

    RowLayout {
        x: card.contentX
        y: card.contentY
        width: card.contentWidth
        height: card.contentHeight
        spacing: Scaler.s(5)

        Repeater {
            model: [
                { label: qsTr("Wi-Fi"), icon: Networking.wifiEnabled ? "󰤨" : "󰤮", active: Networking.wifiEnabled,
                    activate: () => root.open("network", "wifi") },
                { label: qsTr("Bluetooth"), icon: "󰂯", active: Bluetooth.defaultAdapter?.enabled === true,
                    activate: () => root.open("network", "bt") },
                { label: qsTr("Mute or unmute"), icon: root.sink?.muted ? "󰖁" : "󰕾", active: !!root.sink && !root.sink.muted,
                    activate: () => { if (root.sink) root.sink.muted = !root.sink.muted; else root.open("system"); } },
                { label: qsTr("Brightness"), icon: "󰃟", activate: () => root.open("system") },
                { label: qsTr("Settings"), icon: "󰒓", activate: () => root.open("settings") },
                { label: qsTr("Power menu"), icon: "󰐥", activate: () => root.open("system") }
            ]

            delegate: Button {
                id: action
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                enabled: !root.previewMode
                Accessible.name: modelData.label
                ToolTip.visible: hovered
                ToolTip.text: modelData.label
                ToolTip.delay: 400
                onClicked: modelData.activate()

                background: Rectangle {
                    radius: Math.min(height / 2, Scaler.s(11))
                    color: Qt.alpha(action.modelData.active ? kit.accent : ThemeBackend.surface2,
                                    action.down ? 0.55 : action.hovered ? 0.38 : 0.22)
                    border.color: action.hovered ? kit.accent : ThemeBackend.surface2
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: kit.duration(150) } }
                }
                contentItem: Text {
                    text: action.modelData.icon
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: Math.max(12, Math.min(action.height * 0.55, Scaler.s(22)))
                    color: action.modelData.active ? kit.accent : kit.ink
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
