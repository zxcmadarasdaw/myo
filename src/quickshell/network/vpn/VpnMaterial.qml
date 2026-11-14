import QtQuick
import "../../"
import "../../reusables"

// Background material of the VPN page and its sheets. Built on the shell's own
// WallpaperBlur (the same backdrop the Internet card and the other panels use; with
// ThemeBackend.liquidGlass it renders liquid glass), plus cheap overlays per material:
//   matte    solid colour, no blur          glass    blur + soft top highlight
//   liquid   strong rim, light tint          obsidian dark gradient + glossy diagonal
//   minimal  almost transparent, no border  neon     dark + glowing border (3 rings)
// No shader of its own and no continuous animation.
Item {
    id: root

    property var style: VpnAppearance.style
    property real radius: style.radius !== undefined ? style.radius : ThemeBackend.borderRadius
    property real strength: 1.0               // sheets use a bit more opacity
    property bool showBorder: true

    readonly property string material: style.material || "glass"
    readonly property bool blurred: material !== "matte" && (style.blur || 0) > 0.01

    // neon: outer glow rings (drawn outside the rectangle, never take input)
    Repeater {
        model: root.material === "neon" ? 3 : 0
        delegate: Rectangle {
            required property int index
            anchors.fill: parent
            anchors.margins: -(index + 1) * 3
            radius: root.radius + (index + 1) * 3
            color: "transparent"
            border.width: 2
            border.color: Qt.alpha(root.style.glowColor || "#ff4fd8", (0.22 - index * 0.06) * (0.4 + (root.style.glow || 0)))
        }
    }

    Rectangle {
        id: fill
        anchors.fill: parent
        radius: root.radius
        clip: true
        color: {
            let a = Math.min(1, (root.style.opacity !== undefined ? root.style.opacity : 0.8) * root.strength);
            if (root.material === "liquid") a = a * 0.75;
            return Qt.alpha(root.style.background || "#0b0d12", a);
        }
        Behavior on color { ColorAnimation { duration: 260 } }

        WallpaperBlur {
            z: -1
            anchors.fill: parent
            visible: root.blurred
            radius: root.radius
            blurStrength: root.style.blur || 0
            rim: root.material === "liquid" ? 0.9 : 0.45
            tint: root.material === "liquid" ? 0.0 : 0.1
        }

        // glass: soft highlight from the top edge
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: parent.height * 0.45
            visible: root.material === "glass" || root.material === "liquid"
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha("#ffffff", root.material === "liquid" ? 0.10 : 0.06) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // obsidian: dark depth gradient and a glossy diagonal streak
        Rectangle {
            anchors.fill: parent
            visible: root.material === "obsidian"
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha("#ffffff", 0.05) }
                GradientStop { position: 0.35; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.alpha("#000000", 0.35) }
            }
        }
        Rectangle {
            visible: root.material === "obsidian"
            width: parent.width * 0.35
            height: parent.height * 2.2
            x: parent.width * 0.55
            y: -parent.height * 0.6
            rotation: 28
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.alpha("#ffffff", 0.045) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    // border (liquid: double rim)
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        visible: root.showBorder && root.material !== "minimal"
        border.width: root.material === "neon" ? 1.5 : 1
        border.color: root.material === "neon"
            ? Qt.alpha(root.style.glowColor || "#ff4fd8", Math.max(0.35, root.style.borderOpacity || 0))
            : Qt.alpha(root.style.border || "#ffffff", root.style.borderOpacity !== undefined ? root.style.borderOpacity : 0.12)
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1.5
        radius: Math.max(0, root.radius - 1.5)
        color: "transparent"
        visible: root.showBorder && root.material === "liquid"
        border.width: 1
        border.color: Qt.alpha("#ffffff", 0.06)
    }
}
