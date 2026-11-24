# Original Serpantinum Functions Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore a `Super+I` alias for MYO's existing original weather window and close any proven `serpantinum-audio` installer-diagnostic gap without changing Violet Abyss, while preserving the original `Super+S` and `Super+M` flows.

**Architecture:** Reuse the existing `CalendarPopup.qml`, `MusicPopup.qml`, IPC commands, and audio installer. Add only a compositor keybind alias and tests first; modify audio logic only if the focused audit identifies a concrete missing health check. Keep the ZIP as a behavior reference, not a wholesale source overlay.

**Tech Stack:** Hyprland Lua keybinds, QML/Quickshell, Bash installer modules, Python and shell regression tests.

**Spec:** `docs/superpowers/specs/2026-11-24-original-functions-recovery-design.md`

## Global Constraints

- Do not redesign or replace Violet Abyss.
- Do not add permanent weather or music desktop cards.
- Do not remove EasyEffects presets or user audio configuration.
- Do not copy the ZIP wholesale over MYO; preserve MYO-specific fixes.
- Use the ZIP only as an original-behavior reference and copy source files only when a missing implementation is proven.

---

### Task 1: Add and test the weather hotkey alias

**Files:**
- Modify: `compositors/hyprland/config/keybinds.lua` near the existing `Super+S` calendar binding
- Test: `install/tests/keybinds_test.py` (create if no existing parser test covers this file)

**Interfaces:**
- Produces the existing command string `serpantinum msg toggle calendar` under both `SUPER + S` and `SUPER + I`.
- Leaves `SUPER + M` mapped to `serpantinum msg toggle music`.

- [ ] **Step 1: Write the failing parser test**

```python
from pathlib import Path
import re

KEYBINDS = Path(__file__).parents[2] / "compositors/hyprland/config/keybinds.lua"

def commands_for(key):
    text = KEYBINDS.read_text(encoding="utf-8")
    return re.findall(rf'hl\.bind\(mainMod \.\. " \+ {key}", hl\.dsp\.exec_cmd\("([^"]+)"\)\)', text)

def test_weather_aliases_and_music_binding():
    assert commands_for("S") == ["serpantinum msg toggle calendar"]
    assert commands_for("I") == ["serpantinum msg toggle calendar"]
    assert commands_for("M") == ["serpantinum msg toggle music"]
```

- [ ] **Step 2: Run the test and verify the new alias fails**

Run: `python -m pytest install/tests/keybinds_test.py -q`

Expected: the `I` assertion fails because no `Super+I` calendar binding exists.

- [ ] **Step 3: Add the minimal alias**

Immediately after the existing calendar binding in `compositors/hyprland/config/keybinds.lua`, add:

```lua
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("serpantinum msg toggle calendar"))
```

- [ ] **Step 4: Run the focused test**

Run: `python -m pytest install/tests/keybinds_test.py -q`

Expected: all assertions pass.

- [ ] **Step 5: Commit the isolated keybind change**

```bash
git add compositors/hyprland/config/keybinds.lua install/tests/keybinds_test.py
git commit -m "feat: add Super-I weather window alias"
```

### Task 2: Audit and harden audio diagnostics only where missing

**Files:**
- Inspect and modify: `install/modules/audio.sh` only when the baseline audit identifies a missing readiness assertion; otherwise leave it unchanged and record that result
- Inspect call sites: `install/modules/manager.sh`, `install/install.sh`
- Tests: `install/tests/installer_manager_test.sh` plus a focused test block added there for the discovered gap

**Interfaces:**
- `install_audio_daemon` must leave a usable executable at `$AUDIO_PREFIX/bin/serpantinum-audio`.
- The health check must accept a successful `serpantinum-audio version` and a successful control/start probe, and report failure otherwise.
- EasyEffects migration remains opt-in to the existing handoff path and keeps user presets.

- [ ] **Step 1: Run the current audio and manager tests before editing**

Run: `bash install/tests/installer_manager_test.sh` and `python -m pytest install/tests/music_effects_test.py -q`.

Expected: record the baseline result; do not change code if the current checks already cover executable, version, start/control, and failure reporting.

- [ ] **Step 2: Compare the current shell functions with the ZIP reference**

Compare `install/modules/audio.sh` to `serpantinum-master/install/modules/audio.sh` from `E:/Загрузки/serpantinum-master (1).zip`. Keep MYO's retry/cache/diagnostic behavior. Identify a concrete missing assertion before editing.

- [ ] **Step 3: Add a failing regression test for the concrete gap**

Use the existing fake-bin/sandbox conventions in `install/tests/installer_manager_test.sh`; assert the installer emits a failed `serpantinum-audio` component when the executable exists but `version` or its control probe fails, and emits `Installed` only after both succeed.

- [ ] **Step 4: Implement the smallest shell change**

Extend the existing validation function rather than adding a second installer path. Use the repository's current timeout and `FAILED_PKGS` reporting conventions; never remove or rewrite `XDG_DATA_HOME/easyeffects` content.

- [ ] **Step 5: Run the regression and full relevant installer tests**

Run: `bash install/tests/installer_manager_test.sh` and `python -m pytest install/tests/music_effects_test.py -q`.

Expected: all pass with explicit failure output for missing/nonfunctional audio and success output for a working fake engine.

- [ ] **Step 6: Commit only if a concrete audio gap was fixed**

```bash
git add install/modules/audio.sh install/modules/manager.sh install/install.sh install/tests
git commit -m "fix: validate serpantinum-audio readiness"
```

### Task 3: Run integration verification and document limits

**Files:**
- Modify only if needed: `docs/installation/installation.md` or the relevant diagnostics documentation
- Test: existing `install/tests/music_qml_test.py`, `install/tests/themess_test.py`, `install/tests/themess_qml_test.py`, and keybind/audio tests

**Interfaces:**
- Existing CalendarPopup and MusicPopup remain the only large transient weather/music surfaces.
- Violet Abyss theme files under `themess/VioletAbyss` remain unchanged.

- [ ] **Step 1: Run focused QML and themess tests**

```bash
python install/tests/music_qml_test.py
python install/tests/themess_test.py
python install/tests/themess_qml_test.py
```

Expected: pass, with only repository-documented skips.

- [ ] **Step 2: Verify source-level integration**

Confirm `WindowRegistry.js` still maps `music` to `media/MusicPopup.qml`, `CalendarPopup.qml` still exposes forecast selection and animated transitions, and the compositor files contain `Super+S`, `Super+I`, and `Super+M` mappings.

- [ ] **Step 3: Attempt a shell restart only in an available graphical environment**

Use the existing MYO/Quickshell test harness or restart command. Do not claim Fedora graphical success if the VM lacks a working compositor/video backend.

- [ ] **Step 4: Check the diff for Violet Abyss safety**

Run `git diff --stat` and verify no `themess/VioletAbyss` file changed in this recovery work.

- [ ] **Step 5: Commit documentation if changed and report evidence**

Include exact passing test commands and explicitly list any Fedora/real-session checks that remain unverified.
