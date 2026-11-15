# Graph Report - Serpantinum  (2026-11-15)

## Corpus Check
- 469 files · ~416,262 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 806 file(s) not represented in the graph (top: .qml 566, (none) 51, .ttf 33)
- WARNING: 806 of 1384 files seen (58%) have no supported extractor and are missing from this graph entirely. It may look complete while representing only part of the codebase.

## Summary
- 3076 nodes · 5920 edges · 235 communities (171 shown, 64 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 194 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `3c13cff1`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- apptheme.py
- .apply
- GovAlertsLib.js
- wallhub.py
- themess.py
- CanvasMath.js
- Terminal
- CHANGELOG.md
- gpu_policy_test.cjs
- time
- dnf.sh
- TERMS AND CONDITIONS
- window_actions.py
- void.sh
- ThemessTest
- CalculatorEngine.js
- BatteryStub
- serp_pty.py
- serp_vpn.py
- subprocess
- shutil
- WeatherRules.js
- json
- Bridge
- mr-robot/theme.py
- VpnError
- package.json
- MusicEffectsTests
- ProcessExplorerBackendTest
- pages/index.tsx
- dependencies
- status
- ProbeTests
- install_runtime_test.sh
- getting-started/index.tsx
- deps.sh
- theme
- caching.sh
- screenshot.sh
- Script shortcuts
- Overview.md
- qml_check.py
- migrate_easyeffects_test.sh
- scripts/gamma.sh
- serpantinum-gamma
- Options
- deploy.sh
- k9s
- qt/app.json
- serp_diag.py
- pacman.sh
- ui.sh
- frame
- ConverterEngine.js
- LyricsMatch.js
- weather.sh
- serp_vpn_singbox.py
- Installation
- version.sh
- SingboxInstall
- views
- scripts/config.sh
- location.sh
- scripts
- What it serves
- Themess
- GPU Compatibility Manager — этап 2
- Serpantinum на Fedora: проверка, обновление, диагностика
- audio.sh
- ski.sh
- TunLifecycle
- cava/app.json
- firefox/app.json
- halloy/app.json
- table
- kitty/app.json
- wezterm/app.json
- zen-browser/app.json
- migrate_easyeffects.sh
- Serpantinum client
- Music Widget + Audio Studio
- Network, File Dock, Terminal and Process Explorer
- Manual setup
- aerc/app.json
- bat/app.json
- btop/app.json
- emacs/app.json
- foot/app.json
- fzf/app.json
- ghostty/app.json
- helix/app.json
- dialog
- status
- kakoune/app.json
- kde/app.json
- lazygit/app.json
- neovim/app.json
- obsidian/app.json
- spotify-player/app.json
- superfile/app.json
- tmux/app.json
- vscode/app.json
- yazi/app.json
- zathura/app.json
- WeatherKinds.js
- FileDockIcons.js
- Commands
- Commands
- serpantinum-audio
- Installation
- verify.sh
- alacritty/app.json
- atuin/app.json
- claude-code/app.json
- fastfetch/app.json
- fish/app.json
- fuzzel/app.json
- glow/app.json
- gtk/app.json
- k9s/app.json
- konsole/app.json
- lsd/app.json
- micro/app.json
- rio/app.json
- rofi/app.json
- starship/app.json
- sublime/app.json
- vicinae/app.json
- vim/app.json
- wofi/app.json
- zellij/app.json
- ocr_langs.sh
- App theming
- service.sh
- Mr. Robot для Serpantinum
- Serpantinum — Music Widget & Audio Studio 2.0
- WindowRegistry.js
- qs_manager.sh
- Mr. Robot для Serpantinum
- StarHistory/index.tsx
- Mango
- core.sh
- modules/gamma.sh
- migrate.sh
- react
- title
- xray
- i18n.sh
- Website
- NixOS: Flake input
- Overview
- install.sh
- SearchProviders.js
- play_test
- NotesFormat.js
- AudioCache.js
- GpuPolicy.js
- charts
- UsageReadings.js
- get.sh
- modules/config.sh
- daemons.sh
- pm.sh
- state.sh
- telemetry.sh
- sidebars.ts
- colors.sh
- trigger_search.sh
- CLAUDE.md
- home-manager.md
- launch_daemon.sh
- art_fetch.sh
- bluetooth_panel_logic.sh
- location_manual.sh
- lock.sh
- redactor.sh
- reload.sh
- exit.sh
- hibernate.sh
- pam_without_fingerprint.sh
- poweroff.sh
- reboot.sh
- suspend.sh
- volume.sh
- search_control.sh
- BLACK_HOLE_THEMES.md
- update
- Storage
- mr robot/theme.py
- Subscriptions
- VPN subscriptions
- Env
- SingleLinks
- BrokenInput
- Cli
- desktop_input_qml_test.py
- run_helper
- theme_sorter.py
- equalizer.py
- BundleTest
- vpn.sh
- widget_extensions_qml_test.py
- serp_vpn.py
- main
- VpnGeometry.js
- wallpaper_audio_qml_test.py
- serp_gpu.py
- ExitIp
- SingboxChoice
- Mochi Night and ERROR//OVERDRIVE
- clear
- OneClickSetup
- WallpaperAudioActivity.js
- ServiceTest
- SourceRules
- Checks
- SystemFiles
- ProcessBridge
- install-vpn-bundle.sh

## God Nodes (most connected - your core abstractions)
1. `IntegrationTests` - 41 edges
2. `main()` - 33 edges
3. `Terminal()` - 33 edges
4. `VpnError` - 32 edges
5. `ThemessTest` - 30 edges
6. `status()` - 27 edges
7. `vpn_setup()` - 27 edges
8. `update()` - 24 edges
9. `tun_connect()` - 24 edges
10. `RobustnessTests` - 23 edges

## Surprising Connections (you probably didn't know these)
- `download()` --indirect_call--> `status()`  [INFERRED]
  src/scripts/system/serp_vpn_singbox.py → src/scripts/system/serp_vpn.py
- `read_json()` --indirect_call--> `handle()`  [INFERRED]
  src/scripts/theming/apptheme.py → src/scripts/system/serp_procs.py
- `configuration()` --indirect_call--> `item()`  [INFERRED]
  src/scripts/themess/schema.py → src/scripts/wallpaper/wallhub.py
- `items()` --indirect_call--> `item()`  [INFERRED]
  src/scripts/themess/schema.py → src/scripts/wallpaper/wallhub.py
- `screenshot.sh script` --calls--> `ocr_install()`  [EXTRACTED]
  src/scripts/screenshot.sh → src/scripts/ocr_langs.sh

## Import Cycles
- None detected.

## Communities (235 total, 64 thin omitted)

### Community 0 - "apptheme.py"
Cohesion: 0.06
Nodes (75): App, AppError, apply(), _apply(), apply_gsettings(), apply_ini(), apply_json(), apply_line() (+67 more)

### Community 1 - ".apply"
Cohesion: 0.09
Nodes (6): CatalogTests, generate_palette(), IntegrationTests, make_exec(), RobustnessTests, Sandbox

### Community 2 - "GovAlertsLib.js"
Cohesion: 0.08
Nodes (62): areaFromNode(), brightskyToCap(), buildDelivery(), canadaSeverity(), canadaToCap(), capFromJson(), capFromNode(), categoryOk() (+54 more)

### Community 3 - "wallhub.py"
Cohesion: 0.08
Nodes (51): analyse_pixels(), build_filters(), cmd_cache_thumbs(), fetch(), cmd_download(), cmd_edit(), cmd_keys(), cmd_local() (+43 more)

### Community 4 - "themess.py"
Cohesion: 0.09
Nodes (40): MusicThemeTests, choice(), configuration(), items(), number(), pattern(), plain(), validate() (+32 more)

### Community 5 - "CanvasMath.js"
Cohesion: 0.08
Nodes (47): boundsOf(), centerOn(), clamp(), displayGridStep(), expandSelection(), fitRect(), flyStep(), groupOf() (+39 more)

### Community 6 - "Terminal"
Cohesion: 0.10
Nodes (15): blankCell(), blankRow(), cellColors(), charWidth(), colorOf(), defaultAttr(), escapeHtml(), hex2() (+7 more)

### Community 7 - "CHANGELOG.md"
Cohesion: 0.04
Nodes (44): 2.0.3, 2.0.4, 2.0.5, 2.0.6, 2.0.6-1, 2.0.7, 2.1.0, 2.1.1 (+36 more)

### Community 8 - "gpu_policy_test.cjs"
Cohesion: 0.06
Nodes (30): a, assert, b, before, C, cam, fs, P (+22 more)

### Community 10 - "time"
Cohesion: 0.06
Nodes (26): encode(), invoke(), set_path(), wait_for(), load(), Quiet, wait_for(), singleton() (+18 more)

### Community 11 - "dnf.sh"
Cohesion: 0.11
Nodes (22): pm_bootstrap_install(), PM_COPR_MAP, pm_dnf(), pm_dnf_query(), pm_dnf_repo_opts(), pm_enable_copr(), pm_enable_terra(), pm_full_upgrade() (+14 more)

### Community 12 - "TERMS AND CONDITIONS"
Cohesion: 0.06
Nodes (31): 0. Definitions., 10. Automatic Licensing of Downstream Recipients., 11. Patents., 12. No Surrender of Others' Freedom., 13. Remote Network Interaction; Use with the GNU General Public License., 14. Revised Versions of this License., 15. Disclaimer of Warranty., 16. Limitation of Liability. (+23 more)

### Community 13 - "window_actions.py"
Cohesion: 0.08
Nodes (23): actions(), BindPlanTest, FakeHyprctl, FloatToggleTest, KeybindsFileTest, ActionError, address(), bind_plan() (+15 more)

### Community 14 - "void.sh"
Cohesion: 0.10
Nodes (22): pm_disable_display_manager(), pm_enable_display_manager(), pm_enable_hyprland_repo(), PM_EXTERNAL_REPO_MAP, pm_github_asset_url(), pm_install_batch(), pm_install_pkg(), pm_install_release() (+14 more)

### Community 16 - "CalculatorEngine.js"
Cohesion: 0.16
Nodes (24): angleFactor(), applyFunction(), closeParens(), evaluate(), factorial(), fail(), hasOperation(), isValid() (+16 more)

### Community 17 - "BatteryStub"
Cohesion: 0.10
Nodes (8): BatteryStub, DeviceType, Kind, Files, NetworkingStub, UPowerDeviceState, State, UPowerStub

### Community 18 - "serp_pty.py"
Cohesion: 0.07
Nodes (19): cpu_times(), detail(), emit(), gpu_usage(), handle(), main(), memory(), parse_stat() (+11 more)

### Community 19 - "serp_vpn.py"
Cohesion: 0.12
Nodes (32): assign_tags(), _b64decode(), clash_to_server(), detect_country(), _is_ip(), _link_transport(), _looks_like_base64(), make_server() (+24 more)

### Community 20 - "subprocess"
Cohesion: 0.07
Nodes (9): extract_to_md3(), static_palette(), NoPtyTest, archive_bytes(), make_tar(), Messages, Countries, FreshUser (+1 more)

### Community 21 - "shutil"
Cohesion: 0.15
Nodes (15): api_digests(), build_bundle(), build_release(), fetch(), get_asset(), main(), sha256(), collect() (+7 more)

### Community 22 - "WeatherRules.js"
Cohesion: 0.18
Nodes (24): aqiNow(), buildHours(), dailyCondition(), dateKey(), dayEnd(), dayStat(), deltaFromC(), evaluate() (+16 more)

### Community 23 - "json"
Cohesion: 0.13
Nodes (17): command(), main(), build(), _check_value(), clean_outbound(), cmd_apply(), cmd_cleanup(), cmd_run() (+9 more)

### Community 24 - "Bridge"
Cohesion: 0.11
Nodes (10): Bridge, PtyBridgeTest, Восстановление мыши при повторении, Выполненные проверки, Исправление ввода рабочего стола — 14 ноября 2026, Исправление и изменённые файлы, Как установить локальное исправление, Обзор остальных поверхностей и модулей (+2 more)

### Community 25 - "mr-robot/theme.py"
Cohesion: 0.24
Nodes (17): apply_settings(), choose_monitor(), detect_monitor(), file_mode(), import_preset(), installed_source(), json_bytes(), main() (+9 more)

### Community 26 - "VpnError"
Cohesion: 0.15
Nodes (10): build_config(), fetch(), is_url(), load_source_text(), read_setup_file(), singbox_bin(), singbox_check(), singbox_version() (+2 more)

### Community 27 - "package.json"
Cohesion: 0.13
Nodes (19): @docusaurus/module-type-aliases, @docusaurus/tsconfig, @docusaurus/types, @types/react, typescript, browserslist, development, production (+11 more)

### Community 29 - "ProcessExplorerBackendTest"
Cohesion: 0.16
Nodes (4): FakeSystem, load_module(), ProcessExplorerBackendTest, stat_line()

### Community 30 - "pages/index.tsx"
Cohesion: 0.14
Nodes (5): clsx, clsx@^2.0.0, CompositorItem, Home(), HomepageHeader()

### Community 31 - "dependencies"
Cohesion: 0.12
Nodes (17): @docusaurus/core, @docusaurus/faster, @docusaurus/preset-classic, @easyops-cn/docusaurus-search-local, @mdx-js/react, prism-react-renderer, react-dom, config (+9 more)

### Community 32 - "status"
Cohesion: 0.14
Nodes (24): _auth_denied(), check_setup_config(), collect_checks(), _executable(), force_off(), _forget_state(), _helper(), helper_path() (+16 more)

### Community 33 - "ProbeTests"
Cohesion: 0.16
Nodes (3): card(), ProbeTests, runner()

### Community 34 - "install_runtime_test.sh"
Cohesion: 0.33
Nodes (13): bad(), new_home(), ok(), run_deps(), run_verify(), install_runtime_test.sh script, skip(), t() (+5 more)

### Community 35 - "getting-started/index.tsx"
Cohesion: 0.14
Nodes (5): AnimatedLogo(), createShader(), PreviewItem, StepCard, STEPS

### Community 36 - "deps.sh"
Cohesion: 0.23
Nodes (13): bootstrap_installer_deps(), compositor_package_name(), configure_qt_icon_theme(), ensure_quickshell_version(), find_sddm_binary(), install_dependencies(), install_fonts(), quickshell_is_current() (+5 more)

### Community 37 - "theme"
Cohesion: 0.13
Nodes (14): gui, theme, activeBorderColor, cherryPickedCommitBgColor, cherryPickedCommitFgColor, defaultFgColor, inactiveBorderColor, inactiveViewSelectedLineBgColor (+6 more)

### Community 38 - "caching.sh"
Cohesion: 0.15
Nodes (12): IPC_SOCKET, MAIN_QML, QS_CACHE_DIR, QS_DIR, qs_ensure_cache(), QS_LOG_DIR, QS_RUN_DIR, QS_SETTINGS (+4 more)

### Community 39 - "screenshot.sh"
Cohesion: 0.22
Nodes (13): ocr_use_user_data(), capture_region(), crop_source(), get_active_monitor(), is_zero_volume(), ocr_pick_languages(), ocr_recognize(), ocr_run() (+5 more)

### Community 40 - "Script shortcuts"
Cohesion: 0.14
Nodes (14): `brightness`, `exit`, `gamma`, `location`, `location_manual`, `lock`, `lock-redactor`, `redactor` (+6 more)

### Community 41 - "Overview.md"
Cohesion: 0.14
Nodes (9): Autostart, Hyprland, Keybindings, Autostart, Keybindings, Niri, Autostart, Keybindings (+1 more)

### Community 42 - "qml_check.py"
Cohesion: 0.26
Nodes (7): check(), visible_types(), main(), qmldir_types(), read(), Scanner, strip_comments()

### Community 43 - "migrate_easyeffects_test.sh"
Cohesion: 0.21
Nodes (11): check(), LANG, PATH, reset_home(), run_migration(), SERPANTINUM_DIR, migrate_easyeffects_test.sh script, spawn_easyeffects() (+3 more)

### Community 44 - "scripts/gamma.sh"
Cohesion: 0.48
Nodes (13): gamma(), gamma_installed(), gamma_reset(), gamma_running(), gamma_set_auto(), gamma_set_manual(), gamma_start(), gamma_status() (+5 more)

### Community 45 - "serpantinum-gamma"
Cohesion: 0.15
Nodes (13): Building from source, Checking the installation, Color, Commands, Compositors, D-Bus, Day and night schedule, If nothing changes (+5 more)

### Community 46 - "Options"
Cohesion: 0.15
Nodes (13): Bar, Bar modules, Display, Dock, General, Idle, Inputs, Launcher (+5 more)

### Community 47 - "deploy.sh"
Cohesion: 0.24
Nodes (13): configure_sddm_cursor(), deploy_package(), get_wallpaper_dir(), install_bundled_wallpapers(), install_wallpapers(), remove_settings_desktop_entry(), render_wallpaper_progress(), resolve_sddm_backend() (+5 more)

### Community 48 - "k9s"
Cohesion: 0.15
Nodes (12): bgColor, fgColor, logoColor, fgColor, sectionColor, k9s, body, info (+4 more)

### Community 49 - "qt/app.json"
Cohesion: 0.15
Nodes (12): category, default, hint, icon, integrate, name, require_env, QT_QPA_PLATFORMTHEME (+4 more)

### Community 50 - "serp_diag.py"
Cohesion: 0.20
Nodes (16): add_text(), check_qml_module(), crashes(), dependencies(), export(), first_line(), main(), module_checks() (+8 more)

### Community 51 - "pacman.sh"
Cohesion: 0.18
Nodes (3): pm_is_installed(), pm_remove_conflicting_pkg(), pacman.sh script

### Community 52 - "ui.sh"
Cohesion: 0.36
Nodes (10): cleanup_terminal(), draw_banner(), draw_completion_screen(), manage_compositors_menu(), manage_sddm_menu(), read_key(), remove_compositor(), run_installer_ui() (+2 more)

### Community 53 - "frame"
Cohesion: 0.17
Nodes (12): fgColor, focusColor, activeColor, bgColor, fgColor, border, crumbs, menu (+4 more)

### Community 54 - "ConverterEngine.js"
Cohesion: 0.26
Nodes (8): convert(), currencyCodes(), currencyLabel(), factor(), fromKelvin(), toKelvin(), unitIds(), unitLabels()

### Community 55 - "LyricsMatch.js"
Cohesion: 0.35
Nodes (10): buildLrclibSearchQueries(), cleanString(), normalizeForMatch(), pickBestLrclibResult(), pickBestNetEaseSong(), scoreDirect(), scoreDuration(), scoreLrclibCandidate() (+2 more)

### Community 56 - "weather.sh"
Cohesion: 0.39
Nodes (11): fetch_air_quality(), get_data(), get_location(), get_weather_i18n_json(), keep_mtime(), LC_ALL, log_debug(), mark_offline_if_stale() (+3 more)

### Community 57 - "serp_vpn_singbox.py"
Cohesion: 0.08
Nodes (28): arch_name(), asset_name(), bundle_dirs(), candidates(), download(), extract_binary(), find_bundle(), _get() (+20 more)

### Community 59 - "Installation"
Cohesion: 0.18
Nodes (10): Building from source, Checking the installation, D-Bus, Feeds cost nothing when unused, If something looks stuck, In the shell, Installation, Installing and updating (+2 more)

### Community 60 - "version.sh"
Cohesion: 0.24
Nodes (4): format_uuid(), get_telemetry_id(), version.sh script, write_version_state()

### Community 61 - "SingboxInstall"
Cohesion: 0.09
Nodes (4): FakeGithub, serve(), SingboxInstall, Subscriptions

### Community 62 - "views"
Cohesion: 0.18
Nodes (11): bgColor, fgColor, views, bgColor, fgColor, indicator, logs, yaml (+3 more)

### Community 63 - "scripts/config.sh"
Cohesion: 0.31
Nodes (9): _config_ensure_settings(), get_setting(), set_setting(), config.sh script, update_settings_bulk(), check_status(), open_guide(), reset_state() (+1 more)

### Community 64 - "location.sh"
Cohesion: 0.38
Nodes (10): fetch_ip_location(), get_existing_location(), LC_ALL, log_debug(), resolve_location(), save_location(), location.sh script, try_ip_api_com() (+2 more)

### Community 65 - "scripts"
Cohesion: 0.18
Nodes (11): scripts, build, clear, deploy, docusaurus, serve, start, swizzle (+3 more)

### Community 66 - "What it serves"
Cohesion: 0.20
Nodes (10): Brightness, Clipboard, Compositor state, Idle, Keyboard locks, Launcher, Monitors, Screen time (+2 more)

### Community 67 - "Themess"
Cohesion: 0.20
Nodes (8): Example settings.json, Variables, Themess, Возврат к предыдущей версии, Обновление на Fedora 45 + Hyprland, Проверка, Проверка в запущенной сессии Fedora, Формат пакета v1

### Community 68 - "GPU Compatibility Manager — этап 2"
Cohesion: 0.20
Nodes (9): GPU Compatibility Manager — этап 2, Безопасное отображение, Обратимый пробный запуск на Linux, План приёмки на Fedora / Hyprland, Проверки без Linux, Профили, Смена GPU и сохранение данных, Справочные API (+1 more)

### Community 69 - "Serpantinum на Fedora: проверка, обновление, диагностика"
Cohesion: 0.20
Nodes (9): 1. Обновление уже установленного Serpantinum, 2. Проверка окружения после установки, 3. Автоматические тесты, 4. Ручная проверка в сессии Hyprland, 5. Если обои не загружаются, 6. Если после входа пустой рабочий стол, 7. Восстановление рабочего окружения, Serpantinum на Fedora: проверка, обновление, диагностика (+1 more)

### Community 70 - "audio.sh"
Cohesion: 0.33
Nodes (8): audio_arch(), audio_build_from_source(), audio_build_tools(), audio_install_prebuilt(), audio_installed_version(), audio_release_json(), install_audio_daemon(), audio.sh script

### Community 71 - "ski.sh"
Cohesion: 0.31
Nodes (8): configure_ski_defaults(), install_ski(), ski.sh script, ski_installed_version(), ski_release_json(), ski_set_dock_entry(), ski_set_portal_preference(), ski_stage_install()

### Community 72 - "TunLifecycle"
Cohesion: 0.12
Nodes (3): make_exe(), RootEnv, TunLifecycle

### Community 73 - "cava/app.json"
Cohesion: 0.20
Nodes (9): category, default, detect, bin, icon, integrate, name, reload (+1 more)

### Community 74 - "firefox/app.json"
Cohesion: 0.20
Nodes (9): category, detect, bin, flatpak, hint, icon, integrate, name (+1 more)

### Community 75 - "halloy/app.json"
Cohesion: 0.20
Nodes (9): category, detect, bin, flatpak, icon, integrate, name, reload (+1 more)

### Community 76 - "table"
Cohesion: 0.20
Nodes (10): bgColor, fgColor, sorterColor, bgColor, cursorBgColor, cursorFgColor, fgColor, header (+2 more)

### Community 77 - "kitty/app.json"
Cohesion: 0.20
Nodes (9): category, default, detect, bin, icon, integrate, name, reload (+1 more)

### Community 78 - "wezterm/app.json"
Cohesion: 0.20
Nodes (9): category, detect, bin, flatpak, icon, integrate, name, reload (+1 more)

### Community 79 - "zen-browser/app.json"
Cohesion: 0.20
Nodes (9): category, detect, bin, flatpak, hint, icon, integrate, name (+1 more)

### Community 80 - "migrate_easyeffects.sh"
Cohesion: 0.38
Nodes (9): announce(), clean_shipped_autostart(), easyeffects_still_set_up(), notifications_ready(), remove_generated_preset(), migrate_easyeffects.sh script, stop_ee_eq_unit(), stop_own_instance() (+1 more)

### Community 81 - "Serpantinum client"
Cohesion: 0.22
Nodes (9): `config`, `info`, Keybinding examples, Options, Overview, Serpantinum client, `set`, Settings and state (+1 more)

### Community 82 - "Music Widget + Audio Studio"
Cohesion: 0.22
Nodes (6): Music Widget + Audio Studio, Как открыть, Локальные автоматические проверки, Проверка на Fedora 45 / Hyprland / Quickshell 0.3.2, Сохранение и темы, Что управляет звуком

### Community 83 - "Network, File Dock, Terminal and Process Explorer"
Cohesion: 0.20
Nodes (9): Desktop Terminal, Fastfetch Media, File Dock, Manual test checklist (Fedora + Hyprland), Network, File Dock, Terminal and Process Explorer, Network Monitor Pro, Process Explorer, Restrained and Lush looks (+1 more)

### Community 84 - "Manual setup"
Cohesion: 0.22
Nodes (9): 1. Compositor config, 2. Kitty, Cava, and Fastfetch configs, 3. Wallpapers, 4. Serpantinum settings, 5. Services, 6. Qt icon theme, 7. SDDM login screen (optional), 8. First launch (+1 more)

### Community 85 - "aerc/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, hint, icon, integrate, name, templates

### Community 86 - "bat/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, icon, integrate, name, reload, templates

### Community 87 - "btop/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, icon, integrate, name, reload, templates

### Community 88 - "emacs/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, hint, icon, name, reload, templates

### Community 89 - "foot/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, hint, icon, integrate, name, templates

### Community 90 - "fzf/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, hint, icon, integrate, name, templates

### Community 91 - "ghostty/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, icon, integrate, name, reload, templates

### Community 92 - "helix/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, hint, icon, integrate, name, templates

### Community 93 - "dialog"
Cohesion: 0.22
Nodes (9): bgColor, buttonBgColor, buttonFgColor, buttonFocusBgColor, buttonFocusFgColor, fgColor, fieldFgColor, labelFgColor (+1 more)

### Community 94 - "status"
Cohesion: 0.22
Nodes (9): status, addColor, completedColor, errorColor, highlightColor, killColor, modifyColor, newColor (+1 more)

### Community 95 - "kakoune/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, hint, icon, integrate, name, templates

### Community 96 - "kde/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, hint, icon, integrate, name, templates

### Community 97 - "lazygit/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, hint, icon, integrate, name, templates

### Community 98 - "neovim/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, hint, icon, name, reload, templates

### Community 99 - "obsidian/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, flatpak, icon, integrate, name, templates

### Community 100 - "spotify-player/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, hint, icon, integrate, name, templates

### Community 101 - "superfile/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, hint, icon, integrate, name, templates

### Community 102 - "tmux/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, icon, integrate, name, reload, templates

### Community 103 - "vscode/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, flatpak, icon, integrate, name, templates

### Community 104 - "yazi/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, hint, icon, integrate, name, templates

### Community 105 - "zathura/app.json"
Cohesion: 0.22
Nodes (8): category, detect, bin, hint, icon, integrate, name, templates

### Community 106 - "WeatherKinds.js"
Cohesion: 0.39
Nodes (7): card(), palette(), parseGov(), parseWmo(), resolve(), skyColors(), wmoScene()

### Community 107 - "FileDockIcons.js"
Cohesion: 0.42
Nodes (7): baseName(), extOf(), folderIcon(), icon(), isImage(), parse(), tone()

### Community 108 - "Commands"
Cohesion: 0.25
Nodes (8): Commands, `ipc`, `kill`, `launch`, `msg`, `restart`, `settings`, Targets

### Community 109 - "Commands"
Cohesion: 0.25
Nodes (7): Autostart, Commands, Options, Serpantinum daemon, `start`, `status`, `stop`

### Community 110 - "serpantinum-audio"
Cohesion: 0.20
Nodes (10): Dynamic EQ, Fedora check, In the shell, Installation, Installing and updating, Moving from EasyEffects, serpantinum-audio, Video wallpaper audio (+2 more)

### Community 111 - "Installation"
Cohesion: 0.25
Nodes (7): Arch Linux and derivatives, Build from source on Arch, Fedora, Installation, Updating and removing, Void Linux, What the package does

### Community 112 - "verify.sh"
Cohesion: 0.46
Nodes (7): ensure_hyprland_lua_support(), hyprland_version(), verify.sh script, verify_error(), verify_installation(), verify_warning(), version_at_least()

### Community 113 - "alacritty/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, icon, integrate, name, templates

### Community 114 - "atuin/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, icon, integrate, name, templates

### Community 115 - "claude-code/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, hint, icon, name, templates

### Community 116 - "fastfetch/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, hint, icon, name, templates

### Community 117 - "fish/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, hint, icon, name, templates

### Community 118 - "fuzzel/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, icon, integrate, name, templates

### Community 119 - "glow/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, icon, integrate, name, templates

### Community 120 - "gtk/app.json"
Cohesion: 0.25
Nodes (7): category, default, hint, icon, integrate, name, templates

### Community 121 - "k9s/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, hint, icon, name, templates

### Community 122 - "konsole/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, hint, icon, name, templates

### Community 123 - "lsd/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, icon, integrate, name, templates

### Community 124 - "micro/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, hint, icon, name, templates

### Community 125 - "rio/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, icon, integrate, name, templates

### Community 126 - "rofi/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, icon, integrate, name, templates

### Community 127 - "starship/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, icon, integrate, name, templates

### Community 128 - "sublime/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, hint, icon, name, templates

### Community 129 - "vicinae/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, hint, icon, name, templates

### Community 130 - "vim/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, hint, icon, name, templates

### Community 131 - "wofi/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, icon, integrate, name, templates

### Community 132 - "zellij/app.json"
Cohesion: 0.25
Nodes (7): category, detect, bin, icon, integrate, name, templates

### Community 134 - "ocr_langs.sh"
Cohesion: 0.50
Nodes (7): ocr_download(), ocr_install(), ocr_list(), ocr_refresh_available(), ocr_remove(), ocr_valid_code(), ocr_langs.sh script

### Community 136 - "App theming"
Cohesion: 0.29
Nodes (5): App theming, Built-in apps, Command line, Customizing a built-in app, How it works

### Community 137 - "service.sh"
Cohesion: 0.38
Nodes (4): detect_init_system(), enable_system_service(), setup_services(), service.sh script

### Community 138 - "Mr. Robot для Serpantinum"
Cohesion: 0.29
Nodes (6): Mr. Robot для Serpantinum, Импорт через Serpantinum, Откат, Проверка после запуска, Установка из терминала, Файлы

### Community 139 - "Serpantinum — Music Widget & Audio Studio 2.0"
Cohesion: 0.29
Nodes (7): Serpantinum — Music Widget & Audio Studio 2.0, Аудит до изменений, Изменённые и добавленные файлы, Проверки, Результат, Существенные изменения поведения, Что ещё требует Fedora

### Community 140 - "WindowRegistry.js"
Cohesion: 0.38
Nodes (4): getLayout(), getPopupLayout(), getWidgetLauncherEntries(), s()

### Community 141 - "qs_manager.sh"
Cohesion: 0.48
Nodes (6): build_manifest(), handle_wallpaper_prep(), log_widget_launch(), MAGICK_THREAD_LIMIT, send_qs_ipc(), qs_manager.sh script

### Community 142 - "Mr. Robot для Serpantinum"
Cohesion: 0.29
Nodes (6): Mr. Robot для Serpantinum, Импорт через Serpantinum, Откат, Проверка после запуска, Установка из терминала, Файлы

### Community 143 - "StarHistory/index.tsx"
Cohesion: 0.33
Nodes (5): INITIAL_POINTS, MONTH_LABELS, StarHistory(), TimelinePoint, useCountUp()

### Community 144 - "Mango"
Cohesion: 0.33
Nodes (5): Autostart, Keybindings, Limitations, Mango, Tags

### Community 145 - "core.sh"
Cohesion: 0.53
Nodes (5): core_install_prebuilt(), core_installed_version(), core_release_json(), install_core_daemon(), core.sh script

### Community 146 - "modules/gamma.sh"
Cohesion: 0.53
Nodes (5): gamma_install_prebuilt(), gamma_installed_version(), gamma_release_json(), install_gamma_daemon(), gamma.sh script

### Community 147 - "migrate.sh"
Cohesion: 0.53
Nodes (5): backup_compositor_directory(), backup_compositors(), get_compositor_config_dir_name(), migrate_legacy(), migrate.sh script

### Community 149 - "title"
Cohesion: 0.33
Nodes (6): title, bgColor, counterColor, fgColor, filterColor, highlightColor

### Community 150 - "xray"
Cohesion: 0.33
Nodes (6): xray, bgColor, cursorColor, fgColor, graphicColor, showIcons

### Community 151 - "i18n.sh"
Cohesion: 0.53
Nodes (5): detect_system_language(), get_current_language(), is_rtl(), i18n.sh script, t()

### Community 152 - "Website"
Cohesion: 0.33
Nodes (5): Build, Deployment, Installation, Local Development, Website

### Community 153 - "NixOS: Flake input"
Cohesion: 0.40
Nodes (4): Add the flake input, Enable the system module, NixOS: Flake input, Updating

### Community 154 - "Overview"
Cohesion: 0.40
Nodes (5): App theming, Components, Compositor configuration, Installation, Overview

### Community 155 - "install.sh"
Cohesion: 0.40
Nodes (4): I18N_DIR, SERPANTINUM_DIR, SERPANTINUM_INSTALLER, install.sh script

### Community 157 - "play_test"
Cohesion: 0.70
Nodes (3): play_test(), equalizer.sh script, stop_test()

### Community 159 - "AudioCache.js"
Cohesion: 0.70
Nodes (4): arraysEqual(), updateApps(), updateInputs(), updateOutputs()

### Community 161 - "charts"
Cohesion: 0.50
Nodes (4): bgColor, defaultChartColors, defaultDialColors, charts

### Community 162 - "UsageReadings.js"
Cohesion: 0.83
Nodes (3): clamp01(), num(), read()

### Community 196 - "update"
Cohesion: 0.19
Nodes (23): _clean_name(), config_dir(), _find_sub(), load_subs(), _name_from_update(), _new_sub_id(), _record_sub_update(), save_subs() (+15 more)

### Community 198 - "mr robot/theme.py"
Cohesion: 0.25
Nodes (17): apply_settings(), choose_monitor(), detect_monitor(), file_mode(), import_preset(), installed_source(), json_bytes(), main() (+9 more)

### Community 200 - "VPN subscriptions"
Cohesion: 0.12
Nodes (15): Appearance, Command line, Files and privacy, If the service hangs: Force off, Install sing-box, Manual test checklist (Fedora + Hyprland), Ping, Subscriptions (+7 more)

### Community 201 - "Env"
Cohesion: 0.09
Nodes (6): Config, Env, free_port(), Lifecycle, make_fake_singbox(), MissingSingbox

### Community 205 - "desktop_input_qml_test.py"
Cohesion: 0.11
Nodes (11): block(), pump(), singleton(), source(), write(), find_item(), invoke(), load() (+3 more)

### Community 206 - "run_helper"
Cohesion: 0.19
Nodes (4): HelperApply, HelperTemplate, run_helper(), servers_config()

### Community 207 - "theme_sorter.py"
Cohesion: 0.31
Nodes (12): classify_theme(), classify_with_cache(), compute_dominant_hue(), compute_lightness(), fingerprint(), hex_to_rgb(), hue_to_bucket(), load_cache() (+4 more)

### Community 208 - "equalizer.py"
Cohesion: 0.32
Nodes (5): atomic(), Equalizer, main(), number(), validated()

### Community 210 - "vpn.sh"
Cohesion: 0.50
Nodes (3): install_vpn_service(), vpn.sh script, vpn_render_polkit_rules()

### Community 212 - "widget_extensions_qml_test.py"
Cohesion: 0.25
Nodes (7): call(), check_styled_registry(), j(), pty(), registry_variants(), singleton(), write()

### Community 213 - "serp_vpn.py"
Cohesion: 0.10
Nodes (20): _active_sub_name(), build_checks(), country_name(), _default_name(), _die_with_parent(), dns_checks(), _emit(), _ensure_dir() (+12 more)

### Community 214 - "main"
Cohesion: 0.17
Nodes (23): api(), connect(), is_running(), load_settings(), load_settings_readonly(), main(), _merge_settings(), ping() (+15 more)

### Community 215 - "VpnGeometry.js"
Cohesion: 0.27
Nodes (10): attach(), bezier(), chamfer(), layout(), linkPath(), links(), measure(), partial() (+2 more)

### Community 216 - "wallpaper_audio_qml_test.py"
Cohesion: 0.21
Nodes (8): encode(), feed(), invoke(), link(), object_(), position_advances(), stream(), wait_for()

### Community 217 - "serp_gpu.py"
Cohesion: 0.42
Nodes (9): emit(), hwmon_temp(), main(), number(), parse_nvidia(), read(), run_nvidia(), sample_sysfs() (+1 more)

### Community 220 - "Mochi Night and ERROR//OVERDRIVE"
Cohesion: 0.29
Nodes (6): Applying, Changing the girl in the terminal, ERROR//OVERDRIVE, Mochi Night, Mochi Night and ERROR//OVERDRIVE, Workspaces

### Community 221 - "clear"
Cohesion: 0.27
Nodes (8): clear(), disconnect(), _log_tail(), _pid_alive(), pid_path(), _proxy_disconnect(), read_text(), running_pid()

### Community 224 - "WallpaperAudioActivity.js"
Cohesion: 0.60
Nodes (4): activity(), belongsToShell(), isAudible(), isTrue()

## Knowledge Gaps
- **28 isolated node(s):** `SERPANTINUM_INSTALLER`, `SERPANTINUM_DIR`, `I18N_DIR`, `PM_COPR_MAP`, `PM_PKG_MAP` (+23 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1262 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **64 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ThemessTest` connect `ThemessTest` to `subprocess`?**
  _High betweenness centrality (0.019) - this node is a cross-community bridge._
- **What connects `SERPANTINUM_INSTALLER`, `SERPANTINUM_DIR`, `I18N_DIR` to the rest of the system?**
  _28 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `apptheme.py` be split into smaller, more focused modules?**
  _Cohesion score 0.06307456588355465 - nodes in this community are weakly interconnected._
- **Why does `MusicEffectsTests` connect `MusicEffectsTests` to `subprocess`?**
  _High betweenness centrality (0.012) - this node is a cross-community bridge._
- **Should `.apply` be split into smaller, more focused modules?**
  _Cohesion score 0.08823529411764706 - nodes in this community are weakly interconnected._
- **Why does `IntegrationTests` connect `.apply` to `subprocess`?**
  _High betweenness centrality (0.010) - this node is a cross-community bridge._
- **Should `GovAlertsLib.js` be split into smaller, more focused modules?**
  _Cohesion score 0.07836538461538461 - nodes in this community are weakly interconnected._