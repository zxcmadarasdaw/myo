# Проверки этапа 1

17 ноября 2026 года, Windows 11, Git Bash, Python 3.12.10, PySide6/Qt 6.12.0, Lua 5.4 через Lupa во временном каталоге, Node.js и ffmpeg/ffprobe. Дистрибутивы WSL, `hyprctl` и `quickshell` в среде отсутствуют. Настоящие pacman/DNF, systemd/polkit, Hyprland, Wayland, TUN и аудиоустройства целевых систем здесь не запускались.

| Проверка | Результат |
|---|---|
| `bash -n` для tracked `*.sh`, `PKGBUILD`, AUR `*.install` и обоих launcher в `bin/` | Прошло. |
| `bash install/tests/install_runtime_test.sh` | 20 проверок прошли, 1 пропуск Linux-only supervisor (`flock/setsid`). Проверены сохранение правок Hyprland, обновление Canvas, backup, валидация конфигурации и Fedora с неисправной Terra. Менеджеры пакетов и Hyprland подставные. |
| `bash install/tests/migrate_easyeffects_test.sh` | Стенд прервался под Git Bash при создании временных фикстур и получении PID. Тест использует переопределённый PATH с symlink на программы и `/proc/PID/stat`. Результат миграции на Linux остаётся открытым. |
| `canvas_windows_test.lua`, `workspace_navigation_test.lua` | Оба прошли с подставным `hl`. Проверены обе ветки reload, восстановление окон, перемещение и привязки рабочих пространств. |
| `python install/tests/workspace_slots_qml_test.py`, `window_actions_test.py` | Прошли. 22 теста Python и отдельная проверка per-monitor QML. |
| `python install/tests/qml_imports_test.py` | Прошёл. Разрешение типов QML и воссоздание gifLayer в тесте адресации Quickshell. |
| `python -m unittest discover -s install/tests -p 'vpn*test.py'` | 135 тестов, 122 прошли, 13 пропущены. Отдельные утверждения VPN QML в том же запуске прошли. Маршрутизация, права и установка Linux-пакетов этим запуском не подтверждены. |
| Вызов `serp_vpn_packages.py:main(['--terminal', 'install', 'iproute'])` с подставными UID=0, `chdir` и `subprocess.run` | Воспроизведён `NameError: name 'action' is not defined`. Подставной subprocess не вызван. |
| `python install/tests/gpu_compatibility_test.py`, `music_effects_test.py` | 10 и 18 тестов прошли на фикстурах соответственно. |
| `python install/tests/ai_worker_test.py`, `ai_settings_qml_test.py` | 12 тестов worker и QML-стенд прошли. |
| `python install/tests/wallhub_sources_test.py`, `themess_test.py` | Wallpaper Hub 20/20. Themess 23 прошли, 1 пропущен. |
| `python install/tests/fastfetch_media_qml_test.py`, `terminal_pty_test.py` | Fastfetch MP4/WebM/GIF/WebP, пауза и освобождение плеера прошли. PTY — 1 проверка сообщения об ошибке прошла, 5 Linux-only пропущены. |
| `node install/tests/widget_fusion_test.cjs`, `python install/tests/widget_fusion_qml_test.py`, `node install/tests/music_drawer_test.cjs`, `node install/tests/terminal_emulator_test.cjs` | Все прошли. QML с подставной средой, 23 теста эмулятора. |
| Пакеты и upstream Lua | Считаны базы Arch Core/Extra и CachyOS Extra. Подтверждены версии Hyprland `0.57.2-1` и Quickshell `0.3.2-1` из Extra. Тегированный исходник Hyprland сверён для 0.55.0, 0.56.2 и 0.57.0–0.57.2. [Матрица](DEPENDENCIES.md) · [Lua](ARCHITECTURE.md#hyprland-lua-и-ошибка-configunload) |

## Первые команды на тестовой Linux-системе

Проверки ниже читают метаданные текущей системы и не выполняют установку. Код установки проверять на отдельной тестовой системе с сохранёнными настройками.

```bash
cat /etc/os-release
uname -m
Hyprland --version
quickshell --version
Hyprland --verify-config --config "$PWD/compositors/hyprland/hyprland.lua"
python3 install/modules/qml_check.py src/quickshell
command -v python3 ffmpeg ffprobe pw-dump wpctl pactl
systemctl --user status pipewire.socket pipewire-pulse.socket wireplumber.service
systemctl status NetworkManager.service power-profiles-daemon.service
test -c /dev/net/tun
```

На CachyOS сверить `pacman -Si hyprland hyprland-guiutils quickshell qt6-multimedia qt6-multimedia-ffmpeg qt6-imageformats ffmpeg sing-box iproute2 nftables python-yaml`. На Fedora 45 сверить `dnf repoquery hyprland quickshell qt6-qtmultimedia qt6-qtimageformats ffmpeg-free iproute nftables python3-pyyaml` и происхождение COPR-пакетов, если они нужны. При установленных компонентах выполнять те же проверки с установленным пользовательским `hyprland.lua` и смотреть `hyprctl configerrors` из работающего сеанса.

### Матрица ручных проверок для последующих этапов

| Сценарий | Fedora 45 | CachyOS |
|---|---|---|
| Установка и восстановление | Чистая DNF-установка, повтор, сбой репозитория, обновление и restore | Чистая pacman-установка, существующий KDE и свои dotfiles, повтор, сбой, обновление, restore и возврат в KDE |
| Hyprland / Wayland | Super+H/N/M, Super+Left/Right, Super+Z и mouse-drag, reload | То же плюс смена монитора, независимые рабочие пространства, parking/restore окон Canvas |
| Превью и звук | Статичные обои, MP4/WebM/GIF, PipeWire, Smart Wallpaper Audio и Music Studio | То же плюс AMD Mesa/VA-API, Gallery/Cinema и Fastfetch Media |
| VPN | Локальный комплект с Fedora RPM, Proxy, TUN, DNS после disconnect и отказа | Локальный движок, Arch-зависимости, Proxy, TUN, polkit и восстановление маршрутов |
| Данные и модули | Виджеты, темы, AI c и без Ollama, терминал, Launcher, сеть, уведомления | Те же сценарии с нестандартными XDG-путями, Gallery, Canvas и пользовательскими коллекциями |
| После перезапуска | Сохранение данных, журнал, фокус и отсутствие QML-ошибок | Те же проверки, включая возврат в KDE |

## Этап 2

`bash -n` прошёл. `install_runtime_test.sh` под Git Bash — 24 passed, 0 failed, 1 skipped. Дополнительные моки покрывают выбор менеджера при одновременном наличии pacman и dnf, неизвестную платформу, нехватку места, отказ транзакции и повтор, отсутствие повторной установки пакетов, защиту файлов при сбое backup и сохранение другого display manager. Fedora-сценарии с неисправной Terra прошли повторно. Реальные транзакции, загрузка системы и systemd пока не проверены.

## Этап 3

Lua 5.4 с подставным `hl` загрузил Canvas и workspace navigation. Все Lua-файлы компилятора проверены на синтаксис. Прошли 22 Python-теста оконных действий, `workspace_slots_qml_test.py`, `qml_imports_test.py`, `desktop_input_qml_test.py` с нулём ошибок. Композитор и GPU в этих тестах не участвуют. На целевых системах обязательны `Hyprland --verify-config`, `hyprctl configerrors`, запуск Quickshell, reload с отведённым окном Canvas, Super+H/N/M, Super+Left/Right и полноценный mouse-drag.

## Этап 4

Прошли `wallpaper_qml_test.py`, `wallpaper_audio_qml_test.py`, `wallpaper_search_live_test.py --fixtures`, `music_qml_test.py` (60 проверок), `music_effects_test.py` (18), `fastfetch_media_qml_test.py` (24 проверки), `gpu_compatibility_test.py` (10). MP4 и WebM декодировались фактическим Windows Qt. Сетевые адаптеры в тесте Gallery/Cinema и мониторинг PipeWire были подставными. Выбор драйверов, плавность воспроизведения и слышимый эффект на AMD/CachyOS и на Fedora предстоит проверить из пользовательской сессии.

## Этап 5

`install_runtime_test.sh` — 25 passed, 1 Linux-only skip. Arch VPN provider проверен с подстановкой транзакции и подготовки локального комплекта. Сымитированный отказ верификации возвращает ошибку. VPN Python — 135 тестов, 13 пропусков, плюс стенд QML полностью прошёл. SHA-256 всех записей комплекта совпадают, заголовок sing-box — little-endian ELF64 c machine=62 (x86-64), в tar есть биты исполнения. Вызов Fedora terminal helper с подставным subprocess передаёт правильную команду DNF под таймаутом. Реалии systemd, polkit, TUN и DNS нужно подтвердить на целевой машине.

## Этапы 6–8

| Набор | Результат на Windows |
|---|---|
| Bash установщик и обслуживание | 27 проверок прошли, одна пропущена. Временный HOME и подставные транзакции. Проверены XDG и legacy, backup, отказ от восстановления некорректного снимка, restore с предшествующим снимком и архивирование программы с сохранением пользовательского состояния и тем. |
| Python/Qt и Node вне VPN | 28 из 29 запусков прошли. В том числе AI, GPU, Music Studio, Themess, Wallpaper Hub, Fastfetch, терминальный эмулятор, Process Explorer, Widget Fusion/Extensions, Canvas/workspaces и desktop input. `apptheme_test.py` требует Linux-модуль `fcntl` и в Windows остановился на импорте. Пять проверок PTY и одна Themess были штатно пропущены. |
| Wallpaper Hub | Отдельно прошли `--fixtures`, сетевой `--live-images` и `--live-video`. Сетевой видео-тест играет заранее настроенный прямой MP4 из Custom URLs, а не доказывает работу всех поисковых провайдеров. |
| VPN, Lua и синтаксис | 135 VPN-тестов с 13 пропусками, оба Lua-стенда, `bash -n` и статическая проверка QML прошли. |
| Диагностика | Windows smoke-вывод `serp_diag.py summary` — корректный JSON с 24 проверками зависимостей и типов. |

Общий прогон охватил имеющиеся стенды и реальные медиа в Qt там, где среда позволяла. Пропуски и ограничения этапа 1 сохраняются для EasyEffects и Linux supervisor. Установка пакетов, рабочая сессия Hyprland, TUN, PAM, звук PipeWire, AMD VA-API, KDE logout/login и восстановление на целевом Linux считаются непройденными до ручной приёмки. [Порядок приёмки](NEXT_STEPS.md)
