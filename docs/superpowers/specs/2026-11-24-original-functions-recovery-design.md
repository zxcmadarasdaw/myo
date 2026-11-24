# Original Serpantinum Functions Recovery Design

## Goal

Restore the original large weather window and verify the original music/audio path in MYO, using `E:/Загрузки/serpantinum-master (1).zip` as the source of truth while preserving Violet Abyss and existing user settings.

## Findings

- The original large weather UI is `src/quickshell/calendar/CalendarPopup.qml`; it is already present in MYO and matches the ZIP. It provides forecast-day navigation, animated transitions, current conditions, and supplementary metrics.
- The original keybind is `Super+S` (`serpantinum msg toggle calendar`). `Super+I` is free in the current Hyprland keybind file, so it can be added as a compatibility alias without removing `Super+S`.
- The original music UI is `src/quickshell/media/MusicPopup.qml`, opened by `Super+M`; MYO already contains it plus current MPRIS, spectrum, EQ, and music tests.
- MYO already contains the original `serpantinum-audio` installer path and migration safeguards. Changes must be limited to missing diagnostics or health checks discovered by tests, and must never delete or rewrite user EasyEffects presets without explicit migration conditions.

## Design

1. Add `Super+I` as a second Hyprland alias for the existing calendar/weather IPC command. Keep `Super+S` unchanged for upstream compatibility. Apply the same alias only to compositor keybinds that already expose the calendar command if the source and tests show a corresponding safe mapping; do not invent a new weather IPC endpoint.
2. Add regression coverage that parses the Hyprland keybind file and asserts both aliases target `serpantinum msg toggle calendar`, while `Super+M` still targets music. Add a QML/IPC smoke assertion against the existing CalendarPopup and MusicPopup paths rather than cloning either UI.
3. Audit `install/modules/audio.sh`, its manager call sites, and existing audio tests against the ZIP implementation. If a real gap exists, add a narrowly scoped executable/dependency/PipeWire readiness check and make the installer report failure when the engine cannot answer `version` or start its control endpoint. Preserve existing retry and EasyEffects handoff behavior.
4. Run focused shell/Python/QML tests, then the relevant installer and keybind suites. Attempt a real Quickshell restart where the environment supports it; record Fedora/graphics checks that cannot be executed.

## Constraints

- Do not redesign or replace Violet Abyss.
- Do not add permanent weather or music desktop cards.
- Do not remove EasyEffects presets or user audio configuration.
- Do not copy the ZIP wholesale over MYO; preserve MYO-specific fixes.
- Use the ZIP only as an original-behavior reference and copy source files only when a missing implementation is proven.

## Acceptance Criteria

- `Super+S` and `Super+I` open the existing large weather window; day navigation and transitions remain available.
- `Super+M` opens the existing original music interface and its current MPRIS/EQ path remains intact.
- Installer diagnostics fail clearly when `serpantinum-audio` is absent or nonfunctional and pass when its version/control path works.
- Violet Abyss files and layout are unchanged.
- Focused tests pass; any unverified Fedora graphical checks are explicitly reported.
