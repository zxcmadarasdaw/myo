import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../"
import "WidgetFusion.js" as Fusion

ColumnLayout {
    id: controls
    required property var editor
    property real maximumDetailsHeight: 270
    readonly property var group: editor.selectedFusion
    readonly property var options: group ? group.options : Fusion.settings({})
    readonly property bool editingText: titleField.activeFocus || colorField.activeFocus
    property bool expanded: false
    property string notice: ""
    spacing: 4

    function update(key, value) {
        const patch = {};
        patch[key] = value;
        editor.updateFusion(patch);
    }

    RowLayout {
        Layout.fillWidth: true
        Button {
            text: qsTr("Combine Widgets")
            enabled: controls.editor.selectionIdList.length >= 2 && !controls.group
            onClicked: {
                controls.expanded = controls.editor.combineWidgets();
                controls.notice = controls.expanded ? "" : qsTr("Turn off stretch sizing before combining.");
            }
        }
        Button {
            text: qsTr("Fusion")
            checkable: true
            checked: controls.expanded
            enabled: !!controls.group
            onClicked: controls.expanded = checked
        }
    }
    Text {
        Layout.fillWidth: true
        visible: controls.notice !== ""
        text: controls.notice
        color: ThemeBackend.subtext0
        wrapMode: Text.Wrap
    }
    ScrollView {
        id: details
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(detailFields.implicitHeight, controls.maximumDetailsHeight)
        contentWidth: availableWidth
        contentHeight: detailFields.implicitHeight
        clip: true
        visible: controls.expanded && !!controls.group
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            id: detailFields
            width: details.availableWidth
            ComboBox {
                Layout.fillWidth: true
                model: [qsTr("Unified Panel"), qsTr("Seamless"), qsTr("Modular Grid"), qsTr("Horizontal Stack"),
                        qsTr("Vertical Stack"), qsTr("Freeform Fusion"), qsTr("Adaptive Fusion")]
                currentIndex: Fusion.modes.indexOf(controls.options.mode)
                onActivated: controls.update("mode", Fusion.modes[currentIndex])
                Accessible.name: qsTr("Fusion layout")
            }
            ComboBox {
                Layout.fillWidth: true
                model: [qsTr("Premium Matte"), qsTr("Minimal"), qsTr("Editorial"), qsTr("Retro"),
                        qsTr("Technical"), qsTr("Borderless"), qsTr("Compact"), qsTr("Custom")]
                currentIndex: Fusion.styles.indexOf(controls.options.style)
                onActivated: controls.update("style", Fusion.styles[currentIndex])
                Accessible.name: qsTr("Fusion style")
            }
            ComboBox {
                Layout.fillWidth: true
                model: [qsTr("No frame animation"), qsTr("Fade in frame")]
                currentIndex: controls.options.animation === "fade" ? 1 : 0
                onActivated: controls.update("animation", currentIndex === 1 ? "fade" : "none")
                Accessible.name: qsTr("Fusion frame animation")
            }
            Repeater {
                model: [
                    {label: qsTr("Width"), key: "width", from: 40, to: 8192, step: 40},
                    {label: qsTr("Height"), key: "height", from: 40, to: 8192, step: 40},
                    {label: qsTr("Gap"), key: "gap", from: 0, to: 128, step: 4},
                    {label: qsTr("Padding"), key: "padding", from: 0, to: 128, step: 4},
                    {label: qsTr("Columns"), key: "columns", from: 1, to: 12, step: 1},
                    {label: qsTr("Opacity %"), key: "opacity", from: 0, to: 100, step: 5},
                    {label: qsTr("Corner radius"), key: "radius", from: 0, to: 60, step: 2}
                ]
                delegate: RowLayout {
                    id: optionRow
                    required property var modelData
                    readonly property string key: modelData.key
                    readonly property real current: {
                        if (key === "width") return controls.group?.box.w ?? 40;
                        if (key === "height") return controls.group?.box.h ?? 40;
                        return controls.options[key] * (key === "opacity" ? 100 : 1);
                    }
                    Layout.fillWidth: true
                    visible: key !== "columns" || ["grid", "seamless"].includes(controls.options.mode)
                    Label { Layout.fillWidth: true; text: optionRow.modelData.label }
                    SpinBox {
                        id: field
                        from: optionRow.modelData.from; to: optionRow.modelData.to; stepSize: optionRow.modelData.step
                        value: Math.round(optionRow.current)
                        onValueModified: {
                            const key = optionRow.key;
                            if (key === "width") controls.editor.updateFusion({}, value, 0);
                            else if (key === "height") controls.editor.updateFusion({}, 0, value);
                            else controls.update(key, key === "opacity" ? value / 100 : value);
                        }
                        Accessible.name: optionRow.modelData.label
                    }
                }
            }
            TextField {
                id: colorField
                Layout.fillWidth: true
                visible: controls.options.style === "custom"
                placeholderText: qsTr("Background #RRGGBB")
                text: controls.options.background
                maximumLength: 7
                onEditingFinished: controls.update("background", text)
            }
            TextField {
                id: titleField
                Layout.fillWidth: true
                placeholderText: qsTr("Panel title")
                maximumLength: 60
                text: controls.options.title
                onEditingFinished: controls.update("title", text)
            }
            CheckBox {
                text: qsTr("Show dividers")
                enabled: controls.options.style !== "borderless" && controls.options.mode !== "seamless" && controls.options.mode !== "freeform"
                checked: controls.options.dividers
                onToggled: controls.update("dividers", checked)
            }
            CheckBox {
                text: qsTr("Drag one widget")
                visible: controls.options.mode === "freeform"
                checked: controls.editor.editFusionMember
                onToggled: controls.editor.editFusionMember = checked
            }
            RowLayout {
                visible: controls.options.mode !== "freeform"
                Button { text: qsTr("Earlier"); onClicked: controls.editor.updateFusion({}, 0, 0, -1) }
                Button { text: qsTr("Later"); onClicked: controls.editor.updateFusion({}, 0, 0, 1) }
            }
        }
    }
}
