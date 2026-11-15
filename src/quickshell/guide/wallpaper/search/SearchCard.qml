import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as C
import "../../../"

// One search result in the Search Wallpapers grid. Only the small preview
// image the source offers is loaded here (lazily, by the GridView); originals
// are downloaded only on Download / Apply / Edit.
Item {
    id: card
    property var tab: null
    property var r: null
    readonly property var q: r ? (WallpaperSearch.qualityById[r.id] || r.quality || null) : null
    readonly property var pi: r ? (WallpaperSearch.probed[r.id] || null) : null
    readonly property bool isDl: !!(r && WallpaperSearch.downloaded[r.id])
    readonly property bool busy: !!(r && WallpaperSearch.dlItem && WallpaperSearch.dlItem.id === r.id)
    readonly property bool hovered: hover.hovered
    readonly property int w: pi ? pi.width : (r ? r.width : 0)
    readonly property int h: pi ? pi.height : (r ? r.height : 0)
    // Cached copy of the source's thumbnail; some sources (Openverse) serve thumbnails
    // only to the helper, so their cards wait for the cached file.
    readonly property string thumbFile: WallpaperSearch.thumbFor(r)
    readonly property bool thumbFailed: WallpaperSearch.thumbFailed(r) && thumbFile === ""
    function s(v) { return tab ? tab.s(v) : v; }
    function tr(en, ru) { return WallpaperSearch.tr(en, ru); }

    component Icon: Text {
        color: ThemeBackend.text
        font.family: ThemeBackend.iconFont
        font.pixelSize: card.s(15)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    component Badge: Rectangle {
        id: badge
        property string label: ""
        property color tint: ThemeBackend.text
        implicitHeight: card.s(19)
        implicitWidth: badgeText.implicitWidth + card.s(10)
        radius: card.s(6)
        color: Qt.alpha(ThemeBackend.crust, 0.78)
        Text { id: badgeText; anchors.centerIn: parent; text: badge.label; color: badge.tint; font.family: ThemeBackend.fontFamily; font.pixelSize: card.s(10); font.bold: true }
    }
    component Action: Rectangle {
        id: act
        property string icon: ""
        property string hint: ""
        property bool primary: false
        property bool active: true
        signal clicked()
        width: card.s(primary ? 44 : 38)
        height: width
        radius: width / 2
        color: !active ? Qt.alpha(ThemeBackend.surface1, 0.5)
             : primary ? (actMa.containsMouse ? Qt.lighter(ThemeBackend.mauve, 1.12) : ThemeBackend.mauve)
             : (actMa.containsMouse ? Qt.alpha(ThemeBackend.text, 0.28) : Qt.alpha(ThemeBackend.crust, 0.72))
        border.width: primary ? 0 : 1
        border.color: Qt.alpha(ThemeBackend.text, 0.18)
        scale: actMa.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Behavior on color { ColorAnimation { duration: 110 } }
        Icon { anchors.centerIn: parent; text: act.icon; color: act.primary ? ThemeBackend.crust : ThemeBackend.text; font.pixelSize: card.s(act.primary ? 19 : 16) }
        MouseArea {
            id: actMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: act.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (act.active) act.clicked()
        }
        C.ToolTip.visible: actMa.containsMouse && hint !== ""
        C.ToolTip.text: hint
        C.ToolTip.delay: 350
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        anchors.margins: card.s(6)
        radius: card.s(14)
        color: Qt.alpha(ThemeBackend.surface0, card.hovered ? 0.8 : 0.5)
        border.width: 1
        border.color: card.hovered ? Qt.alpha(ThemeBackend.mauve, 0.75) : Qt.alpha(ThemeBackend.surface2, 0.28)
        clip: true
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        HoverHandler { id: hover }

        Rectangle {
            id: media
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.round(width * 0.5625)
            color: ThemeBackend.mantle
            clip: true

            Image {
                id: thumb
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: card.s(420)
                source: !card.r ? "" : card.thumbFile !== "" ? Caching.fileUrl(card.thumbFile) : (card.r.thumbHelper ? "" : (card.r.thumb || ""))
                scale: card.hovered ? 1.05 : 1
                opacity: status === Image.Ready ? 1 : 0
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
            Icon {
                anchors.centerIn: parent
                visible: thumb.status !== Image.Ready
                text: thumb.status === Image.Error || card.thumbFailed ? "󰋩" : "󰸉"
                color: ThemeBackend.surface2
                font.pixelSize: card.s(28)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: card.s(8)
                visible: thumb.status === Image.Error || (card.thumbFailed && thumb.status !== Image.Ready)
                width: parent.width - card.s(20)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: card.tr("no preview: the source may have removed this file", "нет превью: файл мог быть удалён у источника")
                color: ThemeBackend.overlay1
                font.family: ThemeBackend.fontFamily
                font.pixelSize: card.s(10)
            }

            // badges
            Row {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: card.s(7)
                spacing: card.s(4)
                Badge { label: card.r ? (card.r.format || "?").toUpperCase() : ""; tint: ThemeBackend.blue }
                Badge {
                    visible: !!card.r && card.r.kind !== "image"
                    label: card.r ? (card.r.kind === "video" ? "▶ " + card.tr("VIDEO", "ВИДЕО") + (card.r.duration ? " " + WallpaperSearch.fmtDur(card.r.duration) : "") : "GIF") : ""
                    tint: ThemeBackend.teal
                }
                Badge { visible: card.isDl; label: "󰄬"; tint: ThemeBackend.green }
            }
            Badge {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: card.s(7)
                visible: WallpaperSearch.resClass(card.w, card.h) !== ""
                label: WallpaperSearch.resClass(card.w, card.h)
                tint: WallpaperSearch.resClass(card.w, card.h) === "8K" || WallpaperSearch.resClass(card.w, card.h) === "4K" ? ThemeBackend.yellow : ThemeBackend.text
            }
            Badge {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: card.s(7)
                visible: card.q !== null
                label: card.q ? card.q.label : ""
                tint: !card.q ? ThemeBackend.overlay1 : card.q.verdict === "upscale" ? ThemeBackend.red : card.q.verdict === "lowdetail" ? ThemeBackend.peach : card.q.verdict === "ok" ? ThemeBackend.green : ThemeBackend.overlay1
            }

            // click anywhere on the picture: preview
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (card.tab && card.r) card.tab.openPreview(card.r)
            }

            // hover actions
            Rectangle {
                id: shade
                anchors.fill: parent
                opacity: card.hovered || card.busy ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.alpha(ThemeBackend.crust, 0.05) }
                    GradientStop { position: 1.0; color: Qt.alpha(ThemeBackend.crust, 0.78) }
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: card.s(10)
                    spacing: card.s(8)
                    scale: card.hovered ? 1 : 0.88
                    Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack } }
                    Action {
                        objectName: "cardPreview"
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "󰈈"
                        hint: card.tr("Preview", "Просмотр")
                        onClicked: card.tab.openPreview(card.r)
                    }
                    Action {
                        objectName: "cardDownload"
                        anchors.verticalCenter: parent.verticalCenter
                        icon: card.busy ? "󰔟" : card.isDl ? "󰄬" : "󰇚"
                        hint: card.isDl ? card.tr("Downloaded", "Скачано") : card.tr("Download original", "Скачать оригинал")
                        active: !card.isDl && !WallpaperSearch.downloading
                        onClicked: WallpaperSearch.download(card.r, "")
                    }
                    Action {
                        objectName: "cardEdit"
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "󰏫"
                        hint: card.tr("Edit in Wallpaper Studio", "Изменить в Wallpaper Studio")
                        active: WallpaperSearch.ffmpegOk && (card.isDl || !WallpaperSearch.downloading)
                        onClicked: WallpaperSearch.download(card.r, "edit")
                    }
                    Action {
                        objectName: "cardApply"
                        anchors.verticalCenter: parent.verticalCenter
                        primary: true
                        icon: "󰸉"
                        hint: card.tr("Apply as wallpaper", "Установить обоями")
                        active: card.isDl || !WallpaperSearch.downloading
                        onClicked: WallpaperSearch.download(card.r, "apply")
                    }
                }
            }

            // download progress of this card
            Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                height: card.s(3)
                visible: card.busy
                color: ThemeBackend.mauve
                width: WallpaperSearch.dlTotal > 0 ? parent.width * Math.min(1, WallpaperSearch.dlDone / WallpaperSearch.dlTotal) : parent.width * 0.2
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: media.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: card.s(10)
            anchors.rightMargin: card.s(10)
            anchors.topMargin: card.s(6)
            anchors.bottomMargin: card.s(6)
            spacing: card.s(2)
            Text {
                Layout.fillWidth: true
                text: card.r ? (card.r.title || card.r.id) : ""
                color: ThemeBackend.text
                font.family: ThemeBackend.fontFamily
                font.pixelSize: card.s(12)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Text {
                Layout.fillWidth: true
                color: ThemeBackend.subtext0
                font.family: ThemeBackend.fontFamily
                font.pixelSize: card.s(11)
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: {
                    if (!card.r) return "";
                    let parts = [card.r.sourceName, WallpaperSearch.resLabel(card.w, card.h).replace(/ · .*$/, "")];
                    let size = card.pi ? card.pi.size : card.r.size;
                    if (size) parts.push(WallpaperSearch.fmtSize(size));
                    if (!card.r.originalAvailable) parts.push(card.tr("reduced copy", "уменьшенная копия"));
                    return parts.join(" · ");
                }
            }
            Item { Layout.fillHeight: true }
        }
    }
}
