import QtQuick
import QtQuick.Layouts
import "../../"

// Compact colour picker for the VPN appearance tab: saturation/value square, hue bar and a
// HEX field. Emits picked("#rrggbb") while dragging and on a valid HEX entry.
Item {
    id: picker

    property color color: "#7fd4ff"
    signal picked(string hex)

    implicitHeight: Scaler.s(150)

    property real hue: 0
    property real sat: 0
    property real val: 1
    property bool internal: false

    function hex2(n) { let s = Math.round(Math.max(0, Math.min(1, n)) * 255).toString(16); return s.length < 2 ? "0" + s : s; }
    function toHex(c) { return "#" + hex2(c.r) + hex2(c.g) + hex2(c.b); }
    function sync() {
        if (internal) return;
        let c = picker.color;
        if (c.hsvHue >= 0) hue = c.hsvHue;
        sat = c.hsvSaturation;
        val = c.hsvValue;
        hexInput.text = toHex(c);
    }
    function emitHsv() {
        internal = true;
        let c = Qt.hsva(hue, sat, val, 1);
        picker.color = c;
        hexInput.text = toHex(c);
        picker.picked(toHex(c));
        internal = false;
    }
    onColorChanged: sync()
    Component.onCompleted: sync()

    RowLayout {
        anchors.fill: parent
        spacing: Scaler.s(10)

        // saturation / value
        Rectangle {
            id: sv
            Layout.fillHeight: true
            Layout.preferredWidth: height * 1.5
            radius: Scaler.s(8)
            color: Qt.hsva(picker.hue, 1, 1, 1)
            clip: true
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#ffffff" }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: "#000000" }
                }
            }
            Rectangle {
                width: Scaler.s(12); height: width; radius: width / 2
                x: picker.sat * sv.width - width / 2
                y: (1 - picker.val) * sv.height - height / 2
                color: "transparent"
                border.width: 2
                border.color: picker.val > 0.5 ? "#000000" : "#ffffff"
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                function set(m) {
                    picker.sat = Math.max(0, Math.min(1, m.x / sv.width));
                    picker.val = Math.max(0, Math.min(1, 1 - m.y / sv.height));
                    picker.emitHsv();
                }
                onPressed: (m) => set(m)
                onPositionChanged: (m) => { if (pressed) set(m); }
            }
        }

        // hue
        Rectangle {
            id: hueBar
            Layout.fillHeight: true
            Layout.preferredWidth: Scaler.s(16)
            radius: Scaler.s(8)
            gradient: Gradient {
                GradientStop { position: 0.000; color: "#ff0000" }
                GradientStop { position: 0.167; color: "#ffff00" }
                GradientStop { position: 0.333; color: "#00ff00" }
                GradientStop { position: 0.500; color: "#00ffff" }
                GradientStop { position: 0.667; color: "#0000ff" }
                GradientStop { position: 0.833; color: "#ff00ff" }
                GradientStop { position: 1.000; color: "#ff0000" }
            }
            Rectangle {
                width: parent.width + Scaler.s(4); height: Scaler.s(5); radius: height / 2
                x: -Scaler.s(2)
                y: picker.hue * hueBar.height - height / 2
                color: "#ffffff"
                border.width: 1
                border.color: "#000000"
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function set(m) {
                    picker.hue = Math.max(0, Math.min(0.999, m.y / hueBar.height));
                    picker.emitHsv();
                }
                onPressed: (m) => set(m)
                onPositionChanged: (m) => { if (pressed) set(m); }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: Scaler.s(8)
            Rectangle {
                Layout.preferredWidth: Scaler.s(64)
                Layout.preferredHeight: Scaler.s(40)
                radius: Scaler.s(8)
                color: picker.color
                border.width: 1
                border.color: Qt.alpha(ThemeBackend.text, 0.2)
            }
            Rectangle {
                Layout.preferredWidth: Scaler.s(110)
                Layout.preferredHeight: Scaler.s(30)
                radius: Scaler.s(8)
                color: Qt.alpha(ThemeBackend.surface0, 0.7)
                border.width: 1
                border.color: hexInput.activeFocus ? ThemeBackend.blue : Qt.alpha(ThemeBackend.surface2, 0.5)
                TextInput {
                    id: hexInput
                    anchors.fill: parent
                    anchors.leftMargin: Scaler.s(10)
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: "monospace"
                    font.pixelSize: Scaler.s(13)
                    color: ThemeBackend.text
                    selectByMouse: true
                    maximumLength: 7
                    validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{0,6}/ }
                    function commit() {
                        let t = text.trim();
                        if (t.charAt(0) !== "#") t = "#" + t;
                        if (/^#[0-9a-fA-F]{6}$/.test(t)) {
                            picker.internal = true;
                            picker.color = t;
                            picker.internal = false;
                            picker.sync();
                            picker.picked(t.toLowerCase());
                        } else {
                            text = picker.toHex(picker.color);
                        }
                    }
                    onAccepted: commit()
                    onActiveFocusChanged: if (!activeFocus) commit()
                    Accessible.name: "HEX"
                }
            }
        }
    }
}
