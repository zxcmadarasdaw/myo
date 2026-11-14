import QtQuick
import Quickshell
import "../../../"

// Hold-to-confirm power action (sleep / reboot / poweroff) for the user faces.
// Like the default user face: nothing runs on a click; the button has to be
// held until it fills, longer for heavier actions. Releasing early drains it.
Item {
    id: act

    property string cmd: "sleep"           // sleep | reboot | poweroff
    property string icon: ""
    property color color: ThemeBackend.blue
    property real weight: 1.0              // hold time = 550 ms * weight
    property bool lush: false
    property bool armed: true              // false in previews: never runs anything
    readonly property FaceTone tone: FaceTone {}

    property real fill: 0
    property bool triggered: false

    Accessible.role: Accessible.Button
    Accessible.name: act.cmd

    implicitWidth: Scaler.s(40)
    implicitHeight: Scaler.s(32)

    Rectangle {
        id: shell
        anchors.fill: parent
        radius: act.lush ? height / 2 : Math.min(Scaler.s(3), ThemeBackend.clampedBorderRadius)
        antialiasing: true
        clip: true
        color: act.lush ? Qt.alpha(ThemeBackend.text, area.containsMouse ? 0.12 : 0.06) : "transparent"
        border.width: 1
        border.color: act.lush ? Qt.alpha(act.color, area.containsMouse ? 0.7 : 0.35)
                               : (area.containsMouse ? act.tone.hairlineStrong : act.tone.hairline)
        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * act.fill
            radius: shell.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.alpha(act.color, act.lush ? 0.55 : 0.28) }
                GradientStop { position: 1.0; color: Qt.alpha(act.color, act.lush ? 0.85 : 0.28) }
            }
        }

        Text {
            anchors.centerIn: parent
            text: act.icon
            font.family: ThemeBackend.iconFont
            font.pixelSize: Math.min(Scaler.s(16), act.height * 0.5)
            color: area.containsMouse || act.fill > 0 ? act.tone.ink : act.tone.muted
            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: act.armed
        cursorShape: act.triggered ? Qt.ArrowCursor : Qt.PointingHandCursor
        onPressed: if (!act.triggered) { drainAnim.stop(); fillAnim.start(); }
        onReleased: if (!act.triggered && act.fill < 1) { fillAnim.stop(); drainAnim.start(); }
        onCanceled: if (!act.triggered) { fillAnim.stop(); drainAnim.start(); }
    }

    NumberAnimation {
        id: fillAnim
        target: act
        property: "fill"
        to: 1
        duration: Math.max(1, 550 * act.weight * (1 - act.fill))
        easing.type: Easing.InOutCubic
        onFinished: {
            if (act.fill < 1 || !act.armed) return;
            act.triggered = true;
            runTimer.start();
        }
    }

    NumberAnimation {
        id: drainAnim
        target: act
        property: "fill"
        to: 0
        duration: Math.max(1, 900 * act.fill)
        easing.type: Easing.OutCubic
    }

    Timer {
        id: runTimer
        interval: 350
        onTriggered: {
            if (act.armed) {
                let script = Caching.serpantinumDir + "/scripts/system/" + (act.cmd === "sleep" ? "suspend.sh" : act.cmd + ".sh");
                Quickshell.execDetached(["bash", script]);
            }
            act.triggered = false;
            drainAnim.start();
        }
    }
}
