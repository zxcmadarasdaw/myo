import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../../"
import "../../reusables"
import "../../reusables/guide"

DisplayWidgetsState {
    id: displayWidgetsRoot
    subTabIndex: 1

    Flickable {
        anchors.fill: parent
        anchors.topMargin: rootObj.s(8)
        anchors.leftMargin: rootObj.s(8)
        anchors.rightMargin: rootObj.s(8)
        anchors.bottomMargin: rootObj.s(4)
        contentHeight: widgetsCol.implicitHeight + rootObj.s(16)
        contentWidth: width
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            active: parent.moving || parent.movingVertically
            width: rootObj.s(4)
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle {
                implicitWidth: rootObj.s(4)
                radius: rootObj.s(2)
                color: ThemeBackend.surface2
            }
        }

        ColumnLayout {
            id: widgetsCol
            width: parent.width - (parent.contentHeight > parent.height ? rootObj.s(6) : 0)
            spacing: rootObj.s(6)

            FastfetchMediaSection { rootObj: displayWidgetsRoot.rootObj }

            // Atelier widget motion: full | reduced (entrances only) | off (static).
            SettingsRow {
                rootObj: displayWidgetsRoot.rootObj
                settingId: "widgets_atelier_motion"
                icon: "󰐊"
                title: I18n.t("guide.display.widgets.motion.title", "Widget animation")
                description: I18n.t("guide.display.widgets.motion.desc", "Atelier widgets: full motion, only gentle entrances, or completely still. Performance mode always turns it off.")
                searchKeywords: "widgets animation motion reduce atelier weather scene performance"

                Dropdown {
                    readonly property var ids: ["full", "reduced", "off"]
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    Layout.preferredWidth: displayWidgetsRoot.rootObj ? displayWidgetsRoot.rootObj.s(150) : 150
                    Layout.preferredHeight: displayWidgetsRoot.rootObj ? displayWidgetsRoot.rootObj.s(32) : 32
                    accentColor: ThemeBackend.mauve
                    options: [I18n.t("guide.display.widgets.motion.full", "Full"),
                              I18n.t("guide.display.widgets.motion.reduced", "Reduced"),
                              I18n.t("guide.display.widgets.motion.off", "Off")]
                    currentIndex: Math.max(0, ids.indexOf(Config.getSetting("widgetStudio.motion", "full")))
                    onSelected: (index, _) => Config.setSetting("widgetStudio.motion", ids[index])
                    onVisibleChanged: if (!visible && isOpen) closePopup()
                }
            }

            SettingsRow {
                rootObj: displayWidgetsRoot.rootObj
                settingId: "widgets_hide_bar"
                icon: "󰘓"
                title: I18n.t("guide.display.widgets.hide_bar.title", "Hide the bar in the redactor")
                description: I18n.t("guide.display.widgets.hide_bar.desc", "Automatically hide the bar when editing widgets in redactor mode")
                searchKeywords: "widgets redactor hide bar panel"

                Toggle {
                    id: hideBarToggle
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    checked: displayWidgetsRoot.currentHideBarInRedactor
                    accentColor: ThemeBackend.mauve
                    baseColor: ThemeBackend.surface1
                    handleColor: ThemeBackend.crust
                    handleOffColor: ThemeBackend.text
                    onToggled: function(val) {
                        displayWidgetsRoot.currentHideBarInRedactor = val;
                        displayWidgetsRoot.updateWidgetsSetting("hideBarInRedactor", val);
                    }
                }
            }

            SettingsRow {
                rootObj: displayWidgetsRoot.rootObj
                settingId: "widgets_show_distances"
                icon: "󰑭"
                title: I18n.t("guide.display.widgets.show_distances.title", "Show distances")
                description: I18n.t("guide.display.widgets.show_distances.desc", "Show the distances between widgets while moving or resizing them in the redactor")
                searchKeywords: "widgets redactor distances spacing gaps measurements"

                Toggle {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    checked: displayWidgetsRoot.currentShowDistances
                    accentColor: ThemeBackend.mauve
                    baseColor: ThemeBackend.surface1
                    handleColor: ThemeBackend.crust
                    handleOffColor: ThemeBackend.text
                    onToggled: function(val) {
                        displayWidgetsRoot.currentShowDistances = val;
                        displayWidgetsRoot.updateWidgetsSetting("showDistances", val);
                    }
                }
            }

            Repeater {
                model: displayWidgetsRoot.monitorsList
                delegate: WidgetMonitorCard { tab: displayWidgetsRoot }
            }
        }
    }
}
