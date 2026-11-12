import QtQuick
import "../../"
import "../../widgets"

Rectangle {
    id: preview
    required property var packageData
    readonly property var appearance: packageData.appearance || {}
    readonly property var theme: appearance.theme || {}
    readonly property var colors: theme.colors || {}
    readonly property var bar: appearance.bar || null
    readonly property var dock: appearance.dock || null
    readonly property real screenWidth: 1600
    readonly property real screenHeight: 900
    readonly property real factor: width / screenWidth
    readonly property bool verticalBar: !!bar && (bar.position === "left" || bar.position === "right")
    readonly property real barSize: bar && !bar.autohide ? (bar.height || 40) + (bar.style === "fill" ? 0 : 4) : 0
    readonly property var insets: ({
        top: bar && (bar.position || "top") === "top" ? barSize : 0,
        bottom: bar && bar.position === "bottom" ? barSize : 0,
        left: bar && bar.position === "left" ? barSize : 0,
        right: bar && bar.position === "right" ? barSize : 0
    })
    radius: Scaler.s(8)
    color: colors.mantle || ThemeBackend.mantle
    clip: true
    implicitHeight: width * screenHeight / screenWidth

    Image {
        anchors.fill: parent
        source: preview.packageData.image || ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }

    Rectangle {
        visible: !!preview.bar
        readonly property var panel: preview.bar || {}
        width: preview.verticalBar ? (panel.height || 40) * preview.factor : parent.width * (panel.width || 100) / 100
        height: preview.verticalBar ? parent.height * (panel.width || 100) / 100 : (panel.height || 40) * preview.factor
        x: preview.verticalBar ? (panel.position === "right" ? parent.width - width : 0) : (parent.width - width) / 2
        y: preview.verticalBar ? (parent.height - height) / 2 : (panel.position === "bottom" ? parent.height - height : 0)
        radius: panel.style === "fill" ? 0 : 12 * preview.factor
        color: preview.colors.base || ThemeBackend.base
    }

    Rectangle {
        visible: !!preview.dock && preview.dock.enabled !== false
        readonly property var profile: preview.dock || {}
        readonly property bool vertical: profile.position === "left" || profile.position === "right"
        readonly property real thickness: ((profile.elementSize || 44) + 12) * preview.factor
        readonly property real gap: profile.floating ? 10 * preview.factor : 0
        width: vertical ? thickness : parent.width * 0.28
        height: vertical ? parent.height * 0.28 : thickness
        x: vertical ? (profile.position === "left" ? gap : parent.width - width - gap) : (parent.width - width) / 2
        y: vertical ? (parent.height - height) / 2 : (profile.position === "top" ? gap : parent.height - height - gap)
        radius: (preview.theme.borderRadius ?? 8) * preview.factor
        color: preview.colors.surface1 || ThemeBackend.surface1
    }

    Repeater {
        model: preview.packageData.widgets || []
        delegate: Rectangle {
            required property var modelData
            readonly property var alignment: WidgetRegistry.parseAnchors(modelData)
            readonly property real availableWidth: preview.screenWidth - preview.insets.left - preview.insets.right
            readonly property real availableHeight: preview.screenHeight - preview.insets.top - preview.insets.bottom
            readonly property real widgetWidth: modelData.stretchWidth ? preview.screenWidth : modelData.wWidth
            readonly property real widgetHeight: modelData.stretchHeight ? preview.screenHeight : modelData.wHeight
            width: widgetWidth * preview.factor
            height: widgetHeight * preview.factor
            x: {
                if (modelData.stretchWidth) return 0;
                if (!alignment) return modelData.wX * preview.factor;
                const spare = availableWidth - widgetWidth;
                const offset = alignment.h === "right" ? spare - modelData.wX :
                    (alignment.h === "center" ? spare / 2 + modelData.wX : modelData.wX);
                return (preview.insets.left + offset) * preview.factor;
            }
            y: {
                if (modelData.stretchHeight) return 0;
                if (!alignment) return modelData.wY * preview.factor;
                const spare = availableHeight - widgetHeight;
                const offset = alignment.v === "bottom" ? spare - modelData.wY :
                    (alignment.v === "center" ? spare / 2 + modelData.wY : modelData.wY);
                return (preview.insets.top + offset) * preview.factor;
            }
            radius: (preview.theme.borderRadius ?? 8) * preview.factor
            opacity: modelData.wOpacity ?? 1
            rotation: modelData.wRotation || 0
            color: Qt.alpha(preview.colors.surface0 || ThemeBackend.surface0, (preview.theme.elementOpacity ?? 95) / 100)
            border.width: 1
            border.color: Qt.alpha(preview.colors.mauve || ThemeBackend.mauve, 0.5)
            clip: true

            Text {
                anchors.centerIn: parent
                width: parent.width - 4
                text: WidgetRegistry.types[parent.modelData.wType]?.name || parent.modelData.wType
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(7, Math.min(13, parent.height / 2))
                color: preview.colors.text || ThemeBackend.text
            }
        }
    }
}
