import QtQuick
import QtQuick.Layouts
import Quickshell
import "../"
import "../../"
import "../../reusables"
import "../../network/vpn"

// Settings -> Theme -> VPN: appearance of the VPN panel (Super+N -> VPN).
// Every change is a live preview (here and in the open panel) until Apply; Cancel drops
// it, Reset returns to the selected theme's own values, "Save as custom theme" keeps the
// current look as a named preset. Stored in settings.json "vpnAppearance" (VpnAppearance
// singleton): colours, material, lines and layout only, never a subscription or token.
GuideTab {
    id: tab
    subTabIndex: 4

    readonly property var st: VpnAppearance.style
    property string colorKey: "active"
    property string presetName: ""

    function tr(key, en) { return I18n.t("vpn.studio." + key, en); }
    function set(key, value) { VpnAppearance.preview(key, value); }

    // leaving the tab without Apply drops the preview
    onVisibleChanged: if (!visible) VpnAppearance.cancel()
    Component.onDestruction: VpnAppearance.cancel()

    readonly property var materialNames: ({
        matte: tr("material_name.matte", "Matte Dark"), glass: tr("material_name.glass", "Premium Glass"),
        liquid: tr("material_name.liquid", "Liquid Glass"), obsidian: tr("material_name.obsidian", "Obsidian"),
        minimal: tr("material_name.minimal", "Minimal"), neon: tr("material_name.neon", "Neon")
    })
    readonly property var lineNames: ({
        straight: tr("line.straight", "Straight"), curved: tr("line.curved", "Curved"), circuit: tr("line.circuit", "Circuit"),
        flow: tr("line.flow", "Flow"), minimal: tr("line.minimal", "Minimal")
    })
    readonly property var layoutNames: ({
        auto: tr("layouts.auto", "Auto (adapts to size)"), centered: tr("layouts.centered", "Centered"),
        vertical: tr("layouts.vertical", "Vertical"), horizontal: tr("layouts.horizontal", "Horizontal"),
        compact: tr("layouts.compact", "Compact"), expanded: tr("layouts.expanded", "Expanded")
    })
    readonly property var shapeNames: ({
        circle: tr("shape.circle", "Circle"), squircle: tr("shape.squircle", "Squircle"), pill: tr("shape.pill", "Pill")
    })
    readonly property var typeNames: ({
        light: tr("type.light", "Light"), regular: tr("type.regular", "Regular"), bold: tr("type.bold", "Bold")
    })
    readonly property var colorNames: ({
        background: tr("color.background", "Background"), button: tr("color.button", "Button"), line: tr("color.line", "Lines"),
        active: tr("color.active", "Active"), inactive: tr("color.inactive", "Inactive"), text: tr("color.text", "Text"),
        glowColor: tr("color.glow", "Glow"), border: tr("color.border", "Border")
    })

    // ---- small controls -----------------------------------------------------------------
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool selected: false
        signal clicked()
        implicitWidth: chipText.implicitWidth + Scaler.s(24)
        implicitHeight: Scaler.s(30)
        radius: height / 2
        color: selected ? Qt.alpha(ThemeBackend.blue, 0.85) : Qt.alpha(ThemeBackend.surface0, chipMouse.containsMouse ? 0.9 : 0.55)
        border.width: 1
        border.color: selected ? "transparent" : Qt.alpha(ThemeBackend.surface2, 0.5)
        Behavior on color { ColorAnimation { duration: 140 } }
        activeFocusOnTab: true
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: Scaler.s(11)
            color: chip.selected ? ThemeBackend.crust : ThemeBackend.text
        }
        Rectangle {
            anchors.fill: parent; anchors.margins: -3; radius: chip.radius + 3
            color: "transparent"; border.width: 1.5; border.color: ThemeBackend.blue
            visible: chip.activeFocus
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
        Keys.onReturnPressed: chip.clicked()
        Keys.onSpacePressed: chip.clicked()
        Accessible.role: Accessible.RadioButton
        Accessible.name: label
        Accessible.checked: selected
    }

    component Section: ColumnLayout {
        property string title: ""
        Layout.fillWidth: true
        spacing: Scaler.s(8)
        Text {
            text: parent.title
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: Scaler.s(13)
            color: ThemeBackend.text
        }
    }

    component SliderRow: RowLayout {
        id: sr
        property string label: ""
        property real from: 0
        property real to: 1
        property real value: 0
        property int decimals: 2
        signal moved(real v)
        Layout.fillWidth: true
        spacing: Scaler.s(10)
        Text {
            Layout.preferredWidth: Scaler.s(130)
            text: sr.label
            elide: Text.ElideRight
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(12)
            color: ThemeBackend.subtext1
        }
        SliderProgress {
            Layout.fillWidth: true
            Layout.preferredHeight: Scaler.s(14)
            from: sr.from
            to: sr.to
            value: sr.value
            gradColor1: ThemeBackend.blue
            onMoved: (v) => sr.moved(v)
        }
        Text {
            Layout.preferredWidth: Scaler.s(44)
            horizontalAlignment: Text.AlignRight
            text: Number(sr.value).toFixed(sr.decimals)
            font.family: "monospace"
            font.pixelSize: Scaler.s(11)
            color: ThemeBackend.subtext0
        }
    }

    // ---- layout -------------------------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: rootObj.s(8)
        spacing: rootObj.s(8)

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: rootObj.s(12)

            // live preview with the real VPN state (not clickable here)
            ColumnLayout {
                Layout.fillWidth: false                // nested layouts fill by default
                Layout.preferredWidth: Math.max(rootObj.s(300), parent.width * 0.44)
                Layout.fillHeight: true
                spacing: rootObj.s(6)
                Text {
                    text: tab.tr("preview", "Preview") + (VpnAppearance.previewing ? "  ·  " + tab.tr("not_applied", "not applied yet") : "")
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: rootObj.s(12)
                    color: VpnAppearance.previewing ? ThemeBackend.yellow : ThemeBackend.subtext0
                }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.maximumHeight: width * 0.86
                    VpnStudio {
                        anchors.fill: parent
                        enabled: false
                        active: tab.visible
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: tab.tr("preview_note", "The open network panel (Super+N → VPN) shows the preview too.")
                    wrapMode: Text.Wrap
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: rootObj.s(10)
                    color: ThemeBackend.overlay1
                }
                Item { Layout.fillHeight: true }       // keeps the preview at the top
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: col.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: col
                    width: parent.width
                    spacing: rootObj.s(16)

                    // themes
                    Section {
                        title: tab.tr("themes", "Themes")
                        Flow {
                            Layout.fillWidth: true
                            spacing: rootObj.s(8)
                            Repeater {
                                model: VpnAppearance.themes.concat(VpnAppearance.presets.map(p => ({ id: "user:" + p.id, name: p.name, style: p.style, user: true, pid: p.id })))
                                delegate: Rectangle {
                                    id: tile
                                    required property var modelData
                                    readonly property var ts: VpnAppearance.sanitize(modelData.style)
                                    readonly property bool selected: VpnAppearance.currentTheme === modelData.id
                                    width: rootObj.s(118)
                                    height: rootObj.s(74)
                                    radius: rootObj.s(12)
                                    color: ts.background
                                    border.width: selected ? 2 : 1
                                    border.color: selected ? ThemeBackend.blue : Qt.alpha(ts.border, 0.2)
                                    activeFocusOnTab: true
                                    Rectangle {               // mini power button
                                        x: rootObj.s(10); y: rootObj.s(10)
                                        width: rootObj.s(26); height: width
                                        radius: tile.ts.buttonShape === "circle" ? width / 2 : width * 0.3
                                        color: "transparent"
                                        border.width: 2
                                        border.color: tile.ts.active
                                    }
                                    Rectangle { x: rootObj.s(40); y: rootObj.s(22); width: rootObj.s(30); height: Math.max(1, tile.ts.lineWidth); color: tile.ts.line; opacity: 0.8 }
                                    Rectangle { x: rootObj.s(72); y: rootObj.s(16); width: rootObj.s(34); height: rootObj.s(12); radius: rootObj.s(4); color: Qt.alpha(tile.ts.text, 0.15) }
                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: rootObj.s(8)
                                        text: tile.modelData.name
                                        elide: Text.ElideRight
                                        font.family: ThemeBackend.fontFamily
                                        font.weight: Font.Bold
                                        font.pixelSize: rootObj.s(11)
                                        color: tile.ts.text
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: VpnAppearance.previewTheme(tile.modelData.id)
                                    }
                                    Rectangle {               // delete a saved preset
                                        visible: tile.modelData.user === true
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: rootObj.s(4)
                                        width: rootObj.s(20); height: width; radius: width / 2
                                        color: Qt.alpha(ThemeBackend.red, delMouse.containsMouse ? 0.9 : 0.55)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅖"
                                            font.family: ThemeBackend.iconFont
                                            font.pixelSize: rootObj.s(11)
                                            color: ThemeBackend.crust
                                        }
                                        MouseArea {
                                            id: delMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: VpnAppearance.deletePreset(tile.modelData.pid)
                                        }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: tab.tr("delete_preset", "Delete")
                                    }
                                    Keys.onReturnPressed: VpnAppearance.previewTheme(modelData.id)
                                    Keys.onSpacePressed: VpnAppearance.previewTheme(modelData.id)
                                    Accessible.role: Accessible.RadioButton
                                    Accessible.name: modelData.name
                                    Accessible.checked: selected
                                }
                            }
                            Chip {
                                visible: VpnAppearance.currentTheme === "custom"
                                label: tab.tr("custom", "Custom")
                                selected: true
                            }
                        }
                    }

                    // material
                    Section {
                        title: tab.tr("material", "Material")
                        Flow {
                            Layout.fillWidth: true
                            spacing: rootObj.s(6)
                            Repeater {
                                model: VpnAppearance.materials
                                delegate: Chip {
                                    required property string modelData
                                    label: tab.materialNames[modelData] || modelData
                                    selected: tab.st.material === modelData
                                    onClicked: tab.set("material", modelData)
                                }
                            }
                        }
                        SliderRow { label: tab.tr("opacity", "Opacity"); value: tab.st.opacity; onMoved: (v) => tab.set("opacity", v) }
                        SliderRow { label: tab.tr("blur", "Blur"); value: tab.st.blur; onMoved: (v) => tab.set("blur", v) }
                        SliderRow { label: tab.tr("border_opacity", "Border"); value: tab.st.borderOpacity; onMoved: (v) => tab.set("borderOpacity", v) }
                        SliderRow { label: tab.tr("radius", "Corner radius"); from: 0; to: 40; decimals: 0; value: tab.st.radius; onMoved: (v) => tab.set("radius", Math.round(v)) }
                    }

                    // colours
                    Section {
                        title: tab.tr("colors", "Colours")
                        Flow {
                            Layout.fillWidth: true
                            spacing: rootObj.s(6)
                            Repeater {
                                model: VpnAppearance.colorKeys
                                delegate: Rectangle {
                                    id: sw
                                    required property string modelData
                                    readonly property bool selected: tab.colorKey === modelData
                                    width: swRow.implicitWidth + rootObj.s(18)
                                    height: rootObj.s(30)
                                    radius: height / 2
                                    color: selected ? Qt.alpha(ThemeBackend.surface1, 0.95) : Qt.alpha(ThemeBackend.surface0, 0.55)
                                    border.width: selected ? 2 : 1
                                    border.color: selected ? ThemeBackend.blue : Qt.alpha(ThemeBackend.surface2, 0.5)
                                    activeFocusOnTab: true
                                    Row {
                                        id: swRow
                                        anchors.centerIn: parent
                                        spacing: rootObj.s(6)
                                        Rectangle {
                                            width: rootObj.s(14); height: width; radius: width / 2
                                            color: tab.st[sw.modelData] || "#000000"
                                            border.width: 1
                                            border.color: Qt.alpha(ThemeBackend.text, 0.3)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: tab.colorNames[sw.modelData] || sw.modelData
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(11)
                                            color: ThemeBackend.text
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: tab.colorKey = sw.modelData
                                    }
                                    Keys.onReturnPressed: tab.colorKey = modelData
                                    Keys.onSpacePressed: tab.colorKey = modelData
                                    Accessible.role: Accessible.RadioButton
                                    Accessible.name: tab.colorNames[modelData] || modelData
                                    Accessible.checked: selected
                                }
                            }
                        }
                        VpnColorPicker {
                            Layout.fillWidth: true
                            Layout.preferredHeight: rootObj.s(130)
                            color: tab.st[tab.colorKey] || "#ffffff"
                            onPicked: (hex) => tab.set(tab.colorKey, hex)
                        }
                    }

                    // lines
                    Section {
                        title: tab.tr("lines", "Lines")
                        Flow {
                            Layout.fillWidth: true
                            spacing: rootObj.s(6)
                            Repeater {
                                model: VpnAppearance.lineStyles
                                delegate: Chip {
                                    required property string modelData
                                    label: tab.lineNames[modelData] || modelData
                                    selected: tab.st.lineStyle === modelData
                                    onClicked: tab.set("lineStyle", modelData)
                                }
                            }
                        }
                        SliderRow { label: tab.tr("line_width", "Width"); from: 0.5; to: 6; decimals: 1; value: tab.st.lineWidth; onMoved: (v) => tab.set("lineWidth", v) }
                        SliderRow { label: tab.tr("glow", "Glow"); value: tab.st.glow; onMoved: (v) => tab.set("glow", v) }
                        SliderRow { label: tab.tr("speed", "Animation speed"); from: 0.25; to: 3; value: tab.st.animSpeed; onMoved: (v) => tab.set("animSpeed", v) }
                        Row {
                            spacing: rootObj.s(6)
                            Chip { label: tab.tr("anim_on", "Animation on"); selected: tab.st.animate; onClicked: tab.set("animate", true) }
                            Chip { label: tab.tr("anim_off", "Animation off"); selected: !tab.st.animate; onClicked: tab.set("animate", false) }
                        }
                    }

                    // layout, button, type
                    Section {
                        title: tab.tr("layout", "Layout")
                        Flow {
                            Layout.fillWidth: true
                            spacing: rootObj.s(6)
                            Repeater {
                                model: VpnAppearance.layouts
                                delegate: Chip {
                                    required property string modelData
                                    label: tab.layoutNames[modelData] || modelData
                                    selected: tab.st.layout === modelData
                                    onClicked: tab.set("layout", modelData)
                                }
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: rootObj.s(6)
                            Repeater {
                                model: VpnAppearance.buttonShapes
                                delegate: Chip {
                                    required property string modelData
                                    label: tab.shapeNames[modelData] || modelData
                                    selected: tab.st.buttonShape === modelData
                                    onClicked: tab.set("buttonShape", modelData)
                                }
                            }
                            Item { width: rootObj.s(12); height: 1 }
                            Repeater {
                                model: VpnAppearance.typographies
                                delegate: Chip {
                                    required property string modelData
                                    label: tab.typeNames[modelData] || modelData
                                    selected: tab.st.typography === modelData
                                    onClicked: tab.set("typography", modelData)
                                }
                            }
                        }
                    }
                    Item { Layout.preferredHeight: rootObj.s(8) }
                }
            }
        }

        // actions
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false                   // nested layouts fill by default
            Layout.preferredHeight: rootObj.s(40)
            spacing: rootObj.s(8)

            Rectangle {
                Layout.preferredWidth: rootObj.s(200)
                Layout.fillHeight: true
                radius: rootObj.s(10)
                color: Qt.alpha(ThemeBackend.surface0, 0.7)
                border.width: 1
                border.color: nameInput.activeFocus ? ThemeBackend.blue : Qt.alpha(ThemeBackend.surface2, 0.5)
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: rootObj.s(10)
                    verticalAlignment: Text.AlignVCenter
                    visible: nameInput.text === ""
                    text: tab.tr("preset_name", "Name for a custom theme")
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: rootObj.s(11)
                    color: ThemeBackend.overlay1
                }
                TextInput {
                    id: nameInput
                    anchors.fill: parent
                    anchors.leftMargin: rootObj.s(10)
                    anchors.rightMargin: rootObj.s(10)
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    maximumLength: 40
                    color: ThemeBackend.text
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: rootObj.s(12)
                    onAccepted: if (text.trim() !== "") { VpnAppearance.saveAsPreset(text); text = ""; }
                }
            }
            ActionButton {
                text: tab.tr("save_preset", "Save as custom theme")
                enabled: nameInput.text.trim() !== ""
                onClicked: { VpnAppearance.saveAsPreset(nameInput.text); nameInput.text = ""; }
            }
            Item { Layout.fillWidth: true }
            ActionButton { text: tab.tr("reset", "Reset"); onClicked: VpnAppearance.reset() }
            ActionButton { text: tab.tr("cancel", "Cancel"); enabled: VpnAppearance.previewing; onClicked: VpnAppearance.cancel() }
            ActionButton { text: tab.tr("apply", "Apply"); primary: true; enabled: VpnAppearance.previewing; onClicked: VpnAppearance.apply() }
        }
    }

    component ActionButton: Rectangle {
        id: ab
        property string text: ""
        property bool primary: false
        signal clicked()
        Layout.fillHeight: true
        Layout.preferredWidth: abText.implicitWidth + Scaler.s(28)
        radius: Scaler.s(10)
        opacity: enabled ? 1 : 0.45
        color: primary ? Qt.alpha(ThemeBackend.blue, abMouse.containsMouse ? 0.95 : 0.8)
                       : Qt.alpha(ThemeBackend.surface0, abMouse.containsMouse ? 0.95 : 0.7)
        border.width: primary ? 0 : 1
        border.color: Qt.alpha(ThemeBackend.surface2, 0.5)
        activeFocusOnTab: true
        Text {
            id: abText
            anchors.centerIn: parent
            text: ab.text
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: Scaler.s(12)
            color: ab.primary ? ThemeBackend.crust : ThemeBackend.text
        }
        Rectangle {
            anchors.fill: parent; anchors.margins: -3; radius: ab.radius + 3
            color: "transparent"; border.width: 1.5; border.color: ThemeBackend.blue
            visible: ab.activeFocus
        }
        MouseArea {
            id: abMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: ab.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: ab.clicked()
        }
        Keys.onReturnPressed: if (enabled) clicked()
        Keys.onSpacePressed: if (enabled) clicked()
        Accessible.role: Accessible.Button
        Accessible.name: text
    }
}
