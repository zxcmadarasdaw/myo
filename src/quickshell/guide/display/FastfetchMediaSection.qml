import QtQuick
import QtQuick.Layouts
import "../.."
import "../../reusables"
import "../../reusables/guide"
import "../../widgets/faces/terminal"

SettingsGroup {
    id: studio
    expanded: false
    searchable: true
    settingId: "fastfetch_media"
    title: tr("title", "Terminal · Fastfetch Media")
    icon: "󰆍"
    description: tr("hint", "Applies to desktop Terminal widgets in Fastfetch mode.")
    searchKeywords: "terminal fastfetch media logo gif video терминал видео логотип"

    function tr(key, fallback) { return I18n.t("widgets.fastfetchMedia." + key, fallback); }

    function chooseTheme(value) {
        // Theme defaults supply the layout and size until the user overrides them.
        if (value !== FastfetchMedia.theme) FastfetchMedia.set("appearance", {theme: value});
    }

    component StudioToggle: Toggle {
        accentColor: ThemeBackend.mauve
        baseColor: ThemeBackend.surface1
        handleColor: ThemeBackend.crust
        handleOffColor: ThemeBackend.text
    }

    component StudioChoice: Dropdown {
        Layout.preferredWidth: studio.s(150)
        Layout.preferredHeight: studio.s(32)
        fontPixelSize: studio.s(11)
        accentColor: ThemeBackend.mauve
        onVisibleChanged: if (!visible && isOpen) closePopup()
    }

    component StudioSlider: Draggable {
        implicitWidth: studio.s(140)
        implicitHeight: studio.s(18)
        stepSize: 1
        backgroundColor: ThemeBackend.surface0
        accentColor: ThemeBackend.mauve
        handleColor: ThemeBackend.text
    }

    FilePicker {
        id: picker
        rootObj: studio.effectiveRootObj
        nameFilters: FastfetchMedia.filters.concat(FastfetchMedia.filters.map(pattern => pattern.toUpperCase()))
        titleText: studio.tr("choose", "Choose a local media file")
        onFileSelected: (filePath, _) => FastfetchMedia.set("path", filePath)
    }

    subSettings: [
        SettingsRow {
            title: studio.tr("custom", "Use custom media instead of distro logo")
            wrapText: true
            StudioToggle { checked: FastfetchMedia.enabled; onToggled: value => FastfetchMedia.set("enabled", value) }
        },
        SettingsRow {
            title: studio.tr("file", "Media file")
            description: FastfetchMedia.path ? FastfetchMedia.path.split("/").pop() : studio.tr("empty", "No file selected")
            RowLayout {
                ClickButton {
                    height: studio.s(30)
                    textFontSize: studio.s(11)
                    buttonText: studio.tr("chooseButton", "Choose file")
                    onClicked: picker.openWithOptionalPath(Caching.fileUrl(FastfetchMedia.path))
                }
                ClickButton {
                    height: studio.s(30)
                    textFontSize: studio.s(11)
                    buttonText: studio.tr("clear", "Clear")
                    enabled: FastfetchMedia.path !== ""
                    onClicked: FastfetchMedia.set("path", "")
                }
            }
        },
        SettingsRow {
            title: studio.tr("preview", "Preview")
            StudioToggle {
                checked: previewLoader.requested
                enabled: FastfetchMedia.kind !== ""
                onToggled: value => previewLoader.requested = value
            }
        },
        Loader {
            id: previewLoader
            property bool requested: false
            Layout.fillWidth: true
            Layout.preferredHeight: active ? studio.s(250) : 0
            visible: active
            active: studio.visible && studio.isOpen && requested && FastfetchMedia.kind !== ""
            sourceComponent: Rectangle {
                color: Qt.alpha(FastfetchMedia.style.bg, FastfetchMedia.style.alpha)
                radius: Math.max(4, FastfetchMedia.style.radius)
                border.color: Qt.alpha(FastfetchMedia.style.accent, FastfetchMedia.style.border)
                FastfetchMediaPane {
                    id: preview
                    anchors.fill: parent
                    anchors.margins: FastfetchMedia.style.gap / 2
                    active: true
                    preview: true
                }
                TerminalCore {
                    id: previewFetch
                    anchors.fill: preview
                    anchors.leftMargin: preview.leadingSpace
                    anchors.topMargin: preview.topSpace
                    visible: preview.ready
                    live: true
                    viewOnly: true
                    mode: "fastfetch"
                    fetchLayout: FastfetchMedia.layout
                    fontFamily: FastfetchMedia.style.font
                    fontSize: studio.s(11)
                    padding: studio.s(6)
                    theme: ({ fg: FastfetchMedia.style.fg, bg: FastfetchMedia.style.bg, palette: [], boldBright: true })
                }
                Text {
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.margins: studio.s(8)
                    visible: preview.ready && (previewFetch.status === "missing" || previewFetch.status === "error")
                    color: ThemeBackend.text
                    text: previewFetch.status === "missing" ? studio.tr("missingFastfetch", "Install Fastfetch to preview system information.")
                          : previewFetch.statusDetail
                }
                Text {
                    anchors.centerIn: parent
                    width: parent.width - studio.s(24)
                    visible: !preview.ready
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: ThemeBackend.text
                    text: preview.failed ? studio.tr("invalid", "This file could not be opened. The widget uses standard Fastfetch.")
                          : (FastfetchMedia.kind === "video" && !FastfetchMedia.allowMotion)
                            ? studio.tr("limited", "Video is paused by the current performance or recording profile.")
                            : studio.tr("loading", "Loading media…")
                }
            }
        },
        SettingsRow {
            title: studio.tr("theme", "Theme")
            StudioChoice {
                readonly property var ids: Object.keys(FastfetchMedia.presets)
                options: ids.map(key => FastfetchMedia.presets[key].name)
                currentIndex: ids.indexOf(FastfetchMedia.theme)
                onSelected: (index, _) => studio.chooseTheme(ids[index])
            }
        },
        SettingsRow {
            title: studio.tr("layout", "Layout")
            StudioChoice {
                options: [studio.tr("classic", "Classic"), studio.tr("wide", "Wide"), studio.tr("vertical", "Vertical"),
                          studio.tr("floating", "Floating"), studio.tr("minimal", "Minimal")]
                currentIndex: FastfetchMedia.layouts.indexOf(FastfetchMedia.layout)
                onSelected: (index, _) => {
                    const layout = FastfetchMedia.layouts[index];
                    FastfetchMedia.setStyle("layout", layout);
                }
            }
        },
        SettingsRow {
            visible: FastfetchMedia.kind === "animated"
            title: studio.tr("fps", "Animated image frame limit")
            StudioSlider {
                from: 0
                to: 60
                value: FastfetchMedia.animationFps
                valueFormatter: value => value === 0 ? studio.tr("sourceFps", "Source timing") : Math.round(value) + " fps"
                onMoved: value => FastfetchMedia.set("animationFps", value)
            }
        },
        SettingsRow {
            title: studio.tr("position", "Position")
            StudioChoice {
                options: [studio.tr("start", "Start"), studio.tr("center", "Center"), studio.tr("end", "End")]
                currentIndex: FastfetchMedia.positions.indexOf(FastfetchMedia.position)
                onSelected: (index, _) => FastfetchMedia.setStyle("position", FastfetchMedia.positions[index])
            }
        },
        Repeater {
            model: [
                {key: "width", prop: "mediaWidth", label: studio.tr("width", "Media width"), min: 15, max: 100, scale: 1, suffix: "%"},
                {key: "height", prop: "mediaHeight", label: studio.tr("height", "Media height"), min: 15, max: 100, scale: 1, suffix: "%"},
                {key: "zoom", prop: "zoom", label: studio.tr("zoom", "Zoom"), min: 50, max: 200, scale: 100, suffix: "%"},
                {key: "opacity", prop: "opacityValue", label: studio.tr("opacity", "Media opacity"), min: 0, max: 100, scale: 100, suffix: "%"},
                {key: "radius", prop: "radius", label: studio.tr("radius", "Media corner radius"), min: 0, max: 40, scale: 1, suffix: " px"},
                {key: "speed", prop: "speed", label: studio.tr("speed", "Playback speed"), min: 25, max: 200, scale: 100, suffix: "%"}
            ]
            delegate: SettingsRow {
                id: sliderRow
                required property var modelData
                title: modelData.label
                StudioSlider {
                    from: sliderRow.modelData.min
                    to: sliderRow.modelData.max
                    value: FastfetchMedia[sliderRow.modelData.prop] * sliderRow.modelData.scale
                    valueFormatter: value => Math.round(value) + sliderRow.modelData.suffix
                    onMoved: value => {
                        const field = sliderRow.modelData;
                        if (field.key === "speed") FastfetchMedia.set(field.key, value / field.scale);
                        else FastfetchMedia.setStyle(field.key, value / field.scale);
                    }
                }
            }
        },
        SettingsRow {
            title: studio.tr("loop", "Loop")
            StudioToggle { checked: FastfetchMedia.loop; onToggled: value => FastfetchMedia.set("loop", value) }
        },
        SettingsRow {
            title: studio.tr("autoplay", "Autoplay")
            StudioToggle { checked: FastfetchMedia.autoplay; onToggled: value => FastfetchMedia.set("autoplay", value) }
        },
        SettingsRow {
            title: studio.tr("pause", "Pause when the widget is hidden")
            StudioToggle { checked: FastfetchMedia.pauseWhenHidden; onToggled: value => FastfetchMedia.set("pauseWhenHidden", value) }
        },
        SettingsRow {
            title: studio.tr("audio", "Play media audio")
            StudioToggle { checked: FastfetchMedia.playAudio; onToggled: value => FastfetchMedia.set("playAudio", value) }
        },
        SettingsRow {
            visible: FastfetchMedia.playAudio
            title: studio.tr("mix", "Allow mixing with wallpaper audio")
            wrapText: true
            StudioToggle {
                checked: FastfetchMedia.mixWallpaperAudio
                onToggled: value => FastfetchMedia.set("mixWallpaperAudio", value)
            }
        }
    ]
}
