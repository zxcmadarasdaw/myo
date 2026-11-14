import QtQuick
import QtQuick.Layouts
import "../../"
import "../../reusables"
import "../../reusables/guide"

SettingsGroup {
    id: section
    expanded: false
    searchable: true
    settingId: "wallpaper_audio"
    searchKeywords: "wallpaper video audio sound smart duck volume mute звук обоев громкость"
    icon: "󰕾"
    title: section.label("title", "Audio")
    description: {
        if (Wallpaper.audioTrackState === "present") return section.label("track_present", "Audio track available");
        if (Wallpaper.audioTrackState === "absent") return section.label("track_absent", "This video has no audio track");
        return "";
    }

    readonly property var prefs: Wallpaper.audioSettings
    readonly property var monitors: {
        const names = Wallpaper.audioMonitors.slice();
        if (prefs.monitor && !names.includes(prefs.monitor)) names.push(prefs.monitor);
        return names;
    }

    function label(key, fallback) {
        return I18n.t("guide.theme.wallpaper.audio." + key, fallback);
    }

    component AudioToggle: Toggle {
        accentColor: ThemeBackend.mauve
        baseColor: ThemeBackend.surface1
        handleColor: ThemeBackend.crust
        handleOffColor: ThemeBackend.text
    }

    component AudioDropdown: Dropdown {
        Layout.preferredWidth: section.s(160)
        Layout.preferredHeight: section.s(32)
        fontFamily: ThemeBackend.fontFamily
        accentColor: ThemeBackend.mauve
        baseColor: ThemeBackend.surface0
        hoverColor: ThemeBackend.surface1
        dropdownColor: ThemeBackend.surface0
        borderColor: ThemeBackend.surface2
        textColor: ThemeBackend.text
        activeTextColor: ThemeBackend.crust
        cornerRadius: ThemeBackend.borderRadius
        fontPixelSize: section.s(11)
        onVisibleChanged: if (!visible && isOpen) closePopup()
    }

    component AudioSlider: Draggable {
        implicitWidth: section.s(140)
        implicitHeight: section.s(18)
        from: 0
        to: 100
        stepSize: 1
        valueFormatter: v => Math.round(v) + "%"
        backgroundColor: ThemeBackend.surface0
        accentColor: ThemeBackend.mauve
        handleColor: ThemeBackend.text
        handleBorderColor: ThemeBackend.mantle
    }

    subSettings: [
        SettingsRow {
            title: section.label("enable", "Play wallpaper sound")
            AudioToggle {
                checked: section.prefs.enabled
                onToggled: value => Wallpaper.setAudioSetting("enabled", value)
            }
        },
        SettingsRow {
            title: section.label("volume", "Wallpaper volume")
            AudioSlider {
                defaultValue: 50
                value: section.prefs.volume
                onMoved: value => Wallpaper.setAudioSetting("volume", value)
            }
        },
        SettingsRow {
            title: section.label("muted", "Mute")
            AudioToggle {
                checked: section.prefs.muted
                onToggled: value => Wallpaper.setAudioSetting("muted", value)
            }
        },
        SettingsRow {
            title: section.label("source", "Audio source")
            AudioDropdown {
                options: [section.label("primary", "Primary monitor"),
                          section.label("monitor", "Selected monitor"),
                          section.label("none", "No sound")]
                currentIndex: Wallpaper.audioSources.indexOf(section.prefs.source)
                onSelected: (index, value) => {
                    const source = Wallpaper.audioSources[index];
                    if (source === "monitor" && !section.prefs.monitor && Wallpaper.audioMonitors.length > 0) {
                        Config.updateJsonBulk({
                            "wallpaperAudio.source": source,
                            "wallpaperAudio.monitor": Wallpaper.audioMonitors[0]
                        });
                    } else {
                        Wallpaper.setAudioSetting("source", source);
                    }
                }
            }
        },
        SettingsRow {
            visible: section.prefs.source === "monitor"
            title: section.label("monitor", "Selected monitor")
            description: section.prefs.monitor && !Wallpaper.audioMonitors.includes(section.prefs.monitor)
                         ? section.label("disconnected", "Monitor disconnected") : ""
            AudioDropdown {
                options: section.monitors
                currentIndex: options.indexOf(section.prefs.monitor)
                placeholderText: section.label("select_monitor", "Choose monitor")
                onSelected: (index, value) => Wallpaper.setAudioSetting("monitor", value)
            }
        },
        SettingsRow {
            title: "Smart Audio"
            description: Wallpaper.smartAudioActive
                         ? section.label("smart_active", "Other audio activity detected")
                         : (Wallpaper.smartAudioWatching && !Wallpaper.smartAudioReady
                            ? section.label("smart_unavailable", "Waiting for PipeWire") : "")
            AudioDropdown {
                options: [section.label("off", "Off"),
                          section.label("smart_mute", "Mute wallpaper"),
                          section.label("smart_duck", "Lower volume")]
                currentIndex: Wallpaper.audioModes.indexOf(section.prefs.mode)
                onSelected: (index, value) => Wallpaper.setAudioSetting("mode", Wallpaper.audioModes[index])
            }
        },
        SettingsRow {
            visible: section.prefs.mode === "duck"
            title: section.label("duck_volume", "Reduced volume")
            AudioSlider {
                defaultValue: 15
                value: section.prefs.duckVolume
                onMoved: value => Wallpaper.setAudioSetting("duckVolume", value)
            }
        },
        SettingsRow {
            visible: section.prefs.mode !== "off"
            title: section.label("playback", "React to other apps playing sound")
            wrapText: true
            AudioToggle {
                checked: section.prefs.reactToPlayback
                onToggled: value => Wallpaper.setAudioSetting("reactToPlayback", value)
            }
        },
        SettingsRow {
            visible: section.prefs.mode !== "off"
            title: section.label("calls", "React to voice chat and microphone use")
            wrapText: true
            AudioToggle {
                checked: section.prefs.reactToCalls
                onToggled: value => Wallpaper.setAudioSetting("reactToCalls", value)
            }
        },
        SettingsRow {
            title: section.label("lock", "Mute when the screen is locked")
            AudioToggle {
                checked: section.prefs.muteOnLock
                onToggled: value => Wallpaper.setAudioSetting("muteOnLock", value)
            }
        }
    ]
}
