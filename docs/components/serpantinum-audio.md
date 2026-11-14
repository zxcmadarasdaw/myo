---
sidebar_position: 1
title: serpantinum-audio
sidebar_label: serpantinum-audio
slug: /audio
---

# serpantinum-audio

Serpantinum ships its own small audio processor, [serpantinum-audio](https://github.com/ilyamiro/serpantinum-audio). It replaces EasyEffects and depends only on PipeWire. The equalizer, balance, mono, channel swap, dynamic range modes and the dynamic EQ in the music popup all run on it.

It creates a virtual output called **Serpantinum**, processes everything sent to it and plays the result on your real output device. The shell talks to it over a local socket, so changing a slider is instant.

## In the shell

Desktop music widgets now expose the existing music popup through an **Audio Studio** drawer. The compact styles, live ten-band EQ, tone groups, presets and Fedora verification steps are documented in [Music Widget + Audio Studio](../configure/music-studio.md). The original popup and its audio/lyrics pages remain available through Super+M. UI state is committed after a successful engine command; missing effects dependencies are reported without blocking MPRIS controls.

- `serpantinumd start` starts the engine, so it runs whenever the shell does.
- Your real device stays the default output. The engine moves each app's audio onto the **Serpantinum** output, processes it and plays it on the default device, just as EasyEffects did. The **Serpantinum** output appears in the volume popup next to your devices.
- Choosing a device in the volume popup moves the processed audio to that device. The volume keys and every app that asks for the default output see your real device.
- An app you move to another device yourself, for example in pavucontrol, stays there and skips the engine. Apps that pick their own device are left alone too.
- When the engine stops, apps go back to the default device.
- Settings survive a reboot. The engine keeps them in `~/.local/state/serpantinum/audio.state`, and the music popup reads them back from there.

## Video wallpaper audio

Open **Super + H → Theme → Wallpapers → Audio** to enable the soundtrack, set its volume and choose the monitor whose wallpaper can play sound. Wallpaper audio and Smart Audio start disabled. The primary mode uses Qt's primary output. A disconnected selected monitor stays silent until it returns.

Smart Audio can mute the wallpaper or lower it to the configured percentage. The reduced setting caps the normal volume. Use the separate switches for playback and for calls or microphone capture. The wallpaper video continues playing and its volume returns about half a second after the other activity ends. The lock screen has a separate mute switch.

Smart Audio reads events from `pw-dump --monitor` (Fedora package `pipewire-utils`). It checks for running, routed streams and ignores corked playback, muted media, sink monitor captures and Serpantinum's own streams. Call detection uses active microphone capture or a playback stream with a voice role. A program that keeps an unmuted stream running while sending silent samples can still count as active. Wallpaper Studio's edited copies are exported without audio. Use the original video to hear its soundtrack.

### Fedora check

1. Set an MP4 with AAC audio or a WebM with Opus audio as wallpaper. Enable sound, move the volume slider, toggle **Mute**, then select a video without audio. Verify the track indicator and that video keeps playing.
2. Switch between two video wallpapers on two monitors. Change the audio source, unplug the selected monitor and reconnect it. Confirm only the chosen monitor's current wallpaper plays sound. Switch workspaces and lock and unlock the session.
3. Test both Smart Audio modes with Spotify, a browser video, a game and a Discord call. Pause or stop the app and check that wallpaper volume returns. Test each activity switch independently, microphone-only capture, and a screen share using just desktop audio.
4. Restart Serpantinum and verify the settings and single audio source. After exiting Serpantinum, verify that the wallpaper stream and its `pw-dump` subscription have closed.

## Voice chat apps

Voice chat apps skip the engine and play directly on your device, so their sound is not processed. Without this, the people in your call would hear their own voices when you share your screen with audio: the share leaves out the voice chat app, but the engine's processed mix contains its sound too, so it would be captured and sent back to them.

These apps are skipped:

- Discord, including PTB and Canary
- Vesktop, Equibop, Legcord, ArmCord and WebCord
- Zoom
- Teams for Linux
- any app that marks its playback as call audio

Everything these apps play skips the engine, including music and videos in them, so the equalizer and the dynamics modes do not apply to it. If you want an app processed anyway, move it to the **Serpantinum** output in pavucontrol. Each stream is checked only once, when it starts, so nothing switches devices in the middle of playback.

Calls in Telegram and in a browser are still processed, because their call audio looks the same as the rest of their sound.

## Dynamic EQ

The **Dynamic** button on the equalizer page turns on an adaptive tonal balance. It listens to the last few seconds of audio and gently moves the balance toward the typical balance of commercial recordings, without changing loudness. It replaces the manual equalizer while it is on, so the sliders and presets are dimmed until you turn it off.

The design and the research behind each number are described in the [serpantinum-audio README](https://github.com/ilyamiro/serpantinum-audio#dynamic-eq).

## Visualizer

The bar, widget, lock screen and music popup visualizers read their spectrum from `serpantinum-audio visualizer`, a port of cava's processing, so cava is no longer needed. The shell starts it only while music plays and a visualizer is on screen, and stops it shortly after the music stops. It runs separately from the engine, so the visualizer also works when the engine is off. The options are listed in the [serpantinum-audio README](https://github.com/ilyamiro/serpantinum-audio#visualizer).

## Installation

### Installing and updating

The install script downloads the latest release for `x86_64` or `aarch64`, checks it against the published checksums and installs it to `/usr/local/bin`. Prebuilt binaries need glibc 2.39 or newer. On other systems, such as Void Linux musl, the installer installs a compiler and the PipeWire development files and builds it from source. Running the installer again updates it.

The Arch packages bundle a release, and the Nix flake builds it from source.

### Moving from EasyEffects

The first time the installer or the shell runs with the audio engine installed, Serpantinum undoes what it set up for EasyEffects. This runs once:

- stops the EasyEffects instance that the old equalizer started, the one running the `live_eq` preset, and `ee-eq.service` if it is running
- removes the `live_eq` preset that Serpantinum used to generate
- removes the `systemctl --user enable --now easyeffects` line from the autostart file Serpantinum installed for Hyprland, Niri, Sway or Mango, keeping a `.pre-audio-engine.bak` copy of each file it edits

Anything you set up yourself stays as it is. EasyEffects stays installed, and your presets, services and autostart entries are not touched. An EasyEffects you started yourself keeps running. A line you moved or changed, and config files that are links, for example from Home Manager or a dotfiles manager, are left alone too.

If EasyEffects is still running or set to start at login after this, Serpantinum tells you once: in the installer output, or as a notification when the shell starts. EasyEffects can interfere with the audio engine, so turn it off unless you use it for something else, such as microphone effects, which Serpantinum does not do. Depending on how you set it up, that means `systemctl --user disable --now easyeffects`, turning off its start-at-login option in EasyEffects, or removing `services.easyeffects.enable` from your Home Manager configuration.
