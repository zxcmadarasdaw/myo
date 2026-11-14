import QtQuick
import QtQuick.Layouts
import "../../../"
import "../common"

// Calendar, Atelier: a real month grid from the system date (DateTime.now), week start
// and day names from the locale. The arrows page through months; the dot returns to
// today. No events are shown: Serpantinum has no calendar source, and none is invented.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property bool previewMode: false
    property string faceStyle: "retro"
    property real minWidth: 180
    property real minHeight: 150
    property real maxWidth: 900
    property real maxHeight: 900
    property real minAspect: 0.6
    property real maxAspect: 2.6
    property bool isRound: false

    AtelierKit { id: kit; style: root.faceStyle }
    AtelierAppear { target: root; kit: kit }

    readonly property string look: kit.styleId
    readonly property bool boxed: look === "retro" || look === "technical"
    readonly property bool isLive: !!(parent && parent.liveDesktopWidget === true)
    readonly property var locale: Qt.locale()
    readonly property var today: DateTime.now
    property int offset: 0      // months from the current one

    readonly property int shownYear: root.today.getFullYear() + Math.floor((root.today.getMonth() + root.offset) / 12)
    readonly property int shownMonth: ((root.today.getMonth() + root.offset) % 12 + 12) % 12
    readonly property int firstWeekday: root.locale.firstDayOfWeek % 7   // 0 = Sunday

    readonly property var cells: {
        const first = new Date(root.shownYear, root.shownMonth, 1);
        const lead = (first.getDay() - root.firstWeekday + 7) % 7;
        const out = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(root.shownYear, root.shownMonth, 1 - lead + i);
            out.push({
                day: d.getDate(),
                inMonth: d.getMonth() === root.shownMonth,
                isToday: d.getFullYear() === root.today.getFullYear() && d.getMonth() === root.today.getMonth()
                         && d.getDate() === root.today.getDate(),
                weekend: d.getDay() === 0 || d.getDay() === 6
            });
        }
        return out;
    }
    readonly property int rows: root.cells[35].inMonth ? 6 : 5

    readonly property string monthTitle: {
        const name = root.locale.standaloneMonthName(root.shownMonth, Locale.LongFormat);
        return name.charAt(0).toUpperCase() + name.slice(1) + " " + root.shownYear;
    }

    AtelierCard {
        id: card
        kit: kit
        title: root.monthTitle
        detail: root.offset === 0 ? DateTime.dayName : ""
        showHeader: kit.hasHeader
    }

    ColumnLayout {
        x: card.contentX
        y: card.contentY
        width: card.contentWidth
        height: card.contentHeight
        spacing: Scaler.s(4)

        RowLayout {
            Layout.fillWidth: true
            spacing: Scaler.s(4)
            Text {
                Layout.fillWidth: true
                text: card.showHeader ? "" : root.monthTitle
                elide: Text.ElideRight
                font.family: kit.displayFamily
                font.weight: kit.displayWeight
                font.pixelSize: Scaler.s(14)
                color: kit.ink
            }
            Repeater {
                model: [{ t: "‹", step: -1 }, { t: "•", step: 0 }, { t: "›", step: 1 }]
                Rectangle {
                    id: navButton
                    required property var modelData
                    visible: root.isLive && (modelData.step !== 0 || root.offset !== 0)
                    Layout.preferredWidth: Scaler.s(22)
                    Layout.preferredHeight: Scaler.s(18)
                    radius: root.boxed ? 0 : height / 2
                    color: navArea.containsMouse ? Qt.alpha(kit.accent, 0.18) : "transparent"
                    border.width: root.look === "retro" ? 1 : 0
                    border.color: kit.hair
                    Text {
                        anchors.centerIn: parent
                        text: navButton.modelData.t
                        font.family: kit.mono
                        font.pixelSize: Scaler.s(13)
                        color: kit.muted
                    }
                    MouseArea {
                        id: navArea
                        anchors.fill: parent
                        enabled: root.isLive
                        hoverEnabled: root.isLive
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.offset = navButton.modelData.step === 0 ? 0 : root.offset + navButton.modelData.step
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: 7
                Text {
                    required property int index
                    readonly property int weekday: (root.firstWeekday + index) % 7
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    horizontalAlignment: Text.AlignHCenter
                    text: kit.label(root.locale.standaloneDayName(weekday, Locale.ShortFormat).slice(0, root.look === "compact" ? 1 : 2))
                    font.family: kit.labelFamily
                    font.pixelSize: Math.max(Scaler.s(8), Math.min(Scaler.s(11), card.contentHeight * 0.06))
                    color: weekday === 0 || weekday === 6 ? kit.accent2 : kit.faint
                }
            }
        }

        Rectangle {
            visible: root.look === "editorial" || root.look === "technical"
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: kit.hair
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            rowSpacing: root.look === "retro" ? Scaler.s(2) : 0
            columnSpacing: root.look === "retro" ? Scaler.s(2) : 0

            Repeater {
                model: root.rows * 7
                Item {
                    id: dayCell
                    required property int index
                    readonly property var cell: root.cells[index]
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 1

                    Rectangle {
                        anchors.centerIn: parent
                        readonly property real side: Math.min(dayCell.width, dayCell.height) * 0.86
                        width: root.boxed ? dayCell.width : side
                        height: root.boxed ? dayCell.height : side
                        radius: root.boxed || root.look === "editorial" ? 0 : side / 2
                        color: dayCell.cell.isToday ? kit.accent
                               : root.look === "retro" && dayCell.cell.inMonth ? Qt.alpha(ThemeBackend.text, 0.04) : "transparent"
                        border.width: root.look === "retro" && dayCell.cell.inMonth && !dayCell.cell.isToday ? 1 : 0
                        border.color: kit.hair
                    }
                    Text {
                        anchors.centerIn: parent
                        text: dayCell.cell.day
                        font.family: root.boxed ? kit.mono : root.look === "elegant" || root.look === "editorial" ? kit.serif : kit.sans
                        font.weight: dayCell.cell.isToday ? Font.Bold : Font.Normal
                        font.pixelSize: Math.max(Scaler.s(8), Math.min(Scaler.s(15), dayCell.height * 0.5))
                        color: dayCell.cell.isToday ? ThemeBackend.crust
                               : !dayCell.cell.inMonth ? Qt.alpha(kit.faint, 0.5)
                               : dayCell.cell.weekend ? kit.accent2 : kit.ink
                    }
                }
            }
        }
    }
}
