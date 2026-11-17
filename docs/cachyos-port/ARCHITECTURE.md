# Точки адаптации

Инвентаризация ниже описывает исходное состояние перед портом. [Изменения по этапам](PROGRESS.md)

## После адаптации

- Точка входа выбирает DNF/pacman по `/etc/os-release` и проверяет систему до bootstrap. Pacman сначала запрашивает локальную базу и синхронизируется в полной транзакции. Общий deploy и проверка остаются в `install/modules`.
- Пользовательская программа по-прежнему размещается в `~/.local/share/serpantinum`, а настройки и состояние используют пути XDG с выбором уже существующей legacy-копии. `xdg_paths.sh` общий для лаунчера, установки и обслуживания. `maintenance.sh` восстанавливает конфигурацию отдельно от версии установленной программы и работает без root.
- Canvas восстанавливает отведённые окна при `config.reloaded`. Выбранный композитор верифицируется до записи шаблона. Используется PolkitAgent из Quickshell.
- VPN unit и root helpers общие. Локальный проверенный движок переносим между целевыми системами x86_64. RPM-транзакция остаётся в Fedora, pacman-зависимости — в Arch-провайдере. Подмена архитектуры и скачивание движка повторно не нужны для уже пригодного локального движка.

## Установка и запуск

1. [get.sh](../../install/get.sh) загружает входной скрипт. [install.sh](../../install/install.sh) при запуске вне репозитория подготавливает Git-кэш, подключает модули и выбирает режим установки. `--vpn-check` и `--vpn-only` выходят до основного установщика.
2. [pm.sh](../../install/modules/pm.sh) сейчас выбирает провайдер по наличию команды и по умолчанию подставляет pacman. [deps.sh](../../install/modules/deps.sh) отдельно читает `ID`, допускает `cachyos` из списка и передаёт общие имена пакетов провайдеру. Fedora сопоставляет их в [dnf.sh](../../install/modules/pm/dnf.sh). [pacman.sh](../../install/modules/pm/pacman.sh) использует имена напрямую. Есть отдельная реализация Void.
3. [deploy.sh](../../install/modules/deploy.sh), [migrate.sh](../../install/modules/migrate.sh), [config.sh](../../install/modules/config.sh) и [service.sh](../../install/modules/service.sh) размещают программу, конфиги, PAM и службы. Shell-установка создаёт пользовательские ссылки в `~/.local/bin` и системные ссылки в `/usr/local/bin`. [Ski](../../install/modules/ski.sh), audio, gamma и core ставятся отдельно в `/usr/local` из Linux-релизов. У audio есть сборка из исходников.
4. [verify.sh](../../install/modules/verify.sh) проверяет критические пакеты, Quickshell, версию и Lua-конфиг Hyprland, расположение программы и локальное разрешение типов QML. Версия записывается до финальной проверки. Готовность сетевых сервисов и кодеков этим полностью не измеряется.
5. [hyprland.lua](../../compositors/hyprland/hyprland.lua) подключает `env`, `autostart`, `monitors`, `settings`, `keybinds` и `canvas`. [serpantinumd](../../bin/serpantinumd) запускает Quickshell от пользователя, ведёт журнал, использует `flock`, `setsid`, `/proc` и контролирует перезапуски. [caching.sh](../../src/scripts/caching.sh) выставляет `MAIN_QML` и `QS_*`. Установщик, лаунчер, QML и отдельные Python-скрипты смешивают XDG-переменные и жёсткие пути в HOME.
6. [packaging/aur](../../packaging/aur) содержит отдельные рецепты stable и git с `/usr/share/serpantinum`, своими зависимостями и файлом `package-managed`. Они не вызывают shell-установщик, не ставят его VPN unit и polkit helper. Оба рецепта пишут общесистемные portal/mime/environment defaults. Shell-установка не управляется pacman. [updater.py](../../src/scripts/updater.py) проверяет версию в GitHub и подавляет такой запрос при наличии `package-managed`. Документация описывает переустановку и удаление AUR-пакета, отдельного штатного удаления shell-установки нет. [Руководство установки](../installation/installation.md)

## Hyprland Lua и ошибка `config.unload`

- Точка регистрации — [config/canvas.lua](../../compositors/hyprland/config/canvas.lua#L111). Infinite Canvas перемещает подходящие floating-окна и сохраняет в тегах координаты временно отведённых за экран окон. Обработчик восстанавливает их при перезагрузке конфигурации. Другие вызовы `hl.on` находятся в [settings.lua](../../compositors/hyprland/config/settings.lua) (`window.open`) и [autostart.lua](../../compositors/hyprland/config/autostart.lua) (`hyprland.start`).
- Установщик требует Hyprland **≥ 0.55.0** для чтения `hyprland.lua`. Текущий `canvas.lua` выбирает `config.unload` по major/minor с 0.57, а для более ранних сборок регистрирует `config.reloaded` и восстанавливает окна по тегам в новом состоянии Lua.
- Проверены списки разрешённых событий и регистрация в тегированных исходниках Hyprland. В **0.55.0 и 0.56.2** есть `config.reloaded`, `config.unload` отсутствует. В **0.57.0, 0.57.1 и 0.57.2** есть оба, `config.unload` привязан к выгрузке. [0.55.0](https://github.com/hyprwm/Hyprland/blob/v0.55.0/src/config/lua/LuaEventHandler.cpp) · [0.56.2](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/config/lua/LuaEventHandler.cpp) · [0.57.0](https://github.com/hyprwm/Hyprland/blob/v0.57.0/src/config/lua/LuaEventHandler.cpp) · [0.57.1](https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/config/lua/LuaEventHandler.cpp) · [0.57.2](https://github.com/hyprwm/Hyprland/blob/v0.57.2/src/config/lua/LuaEventHandler.cpp)
- Ранее наблюдавшаяся ошибка соответствует попытке зарегистрировать отсутствующее событие. Точный бинарник и тогдашний развернутый `canvas.lua` в этой среде не проверены. Если ошибка возникает на системе, где `--version` показывает ≥0.57, зафиксировать версию и commit сборки, проверить фактический путь конфигурации, запустить `Hyprland --verify-config --config …` и сверить API именно этого бинарника. При расхождении версии с фактическим API порог версии недостаточен.
- [window_actions.py](../../src/scripts/system/window_actions.py) и QML вызывают `hyprctl` и читают JSON, а также используют `hyprctl eval` с `hl.dsp` и Lua-состоянием. Ветки диагностики определяют изменения по версии, но минимальная версия установщика сама по себе не проверяет все используемые структуры. Для IPC, mouse-drag, независимых рабочих пространств и Canvas нужен тест запущенного композитора.

## Службы и модули

| Область | Точки входа и системный контракт |
|---|---|
| QML и Wayland | Quickshell ≥ 0.3.0 по установщику. Используются `Quickshell.Hyprland`, `Wayland`, `Networking`, `Bluetooth`, `Services.Pam/Polkit/Pipewire/Mpris/Notifications/SystemTray/UPower` и Qt 6 Quick, Controls, Effects, Dialogs, Multimedia. Нужен выпуск Quickshell с этими модулями и согласованной Qt ABI. Локальный QML-чек проверяет импорты проекта, а не сборочные возможности пакета. |
| Audio / Music Studio | User units `pipewire.socket`, `pipewire-pulse.socket`, `wireplumber.service`, инструменты `pw-dump`, `wpctl`, `pactl`, MPRIS через D-Bus и отдельный `serpantinum-audio`. [migrate_easyeffects.sh](../../src/scripts/migrate_easyeffects.sh) переносит старую настройку, ищет собственный процесс и legacy-службу `ee-eq.service`. |
| Wallpaper Hub / Themess | [wallhub.py](../../src/scripts/wallpaper/wallhub.py) использует Python, HTTPS и ffmpeg/ffprobe. Qt Multimedia декодирует видео в Gallery, Cinema и Wallpaper Engine. GIF/WebP используют плагины изображений, тема Themess может преобразовывать оригинал через ffmpeg. |
| VPN | [vpn.sh](../../install/modules/vpn.sh) ставит unit, polkit и root-owned helpers. [serp_vpn.py](../../src/scripts/system/serp_vpn.py) управляет Proxy/TUN и использует Python/PyYAML, `ip`, `nft`, D-Bus/polkit и systemd. [Unit](../../install/system/vpn/serpantinum-vpn.service) запускается по запросу, требует `/dev/net/tun` для TUN, использует ограниченные сетевые capabilities и root-owned конфигурацию. Proxy запускается в пользовательском контексте. |
| AI | [AiService.qml](../../src/quickshell/singletons/system/AiService.qml) запускает [worker.py](../../src/scripts/ai/worker.py). Python stdlib, SQLite и локальный HTTP к Ollama. Сам Ollama и модели живут вне установщика. Сервер, модель, аппаратное ускорение и история отдельно проверяются на Linux. |
| GPU и Process Explorer | Linux DRM/sysfs и procfs, необязательные `nvidia-smi`, `vainfo`, утилиты Vulkan/GL, ffmpeg. [gpu_compatibility.py](../../src/scripts/system/gpu_compatibility.py) проверяет возможности доступного устройства. Отсутствие утилиты или прав к render-node нельзя трактовать как наличие ускорения. |
| Terminal / Fastfetch | [TerminalCore.qml](../../src/quickshell/widgets/faces/terminal/TerminalCore.qml) запускает [serp_pty.py](../../src/scripts/system/serp_pty.py), Python PTY с Linux-процессами и локальным shell. Fastfetch, cmatrix, cava и пользовательские monitor-команды выполняются по наличию. Медиа Fastfetch дополнительно используют Qt. |
| Виджеты, Launcher, уведомления, сеть | Widget Fusion/Editor и Canvas используют существующий QML и настройки. Launcher читает Desktop Entries и использует XDG/DBus. Сеть использует NetworkManager, Bluetooth — BlueZ, уведомления — Quickshell Notifications. На машине с KDE проверить совместное использование системных служб и независимость графических сессий. |

Поиск по исходникам не выявил команд `setenforce`, `restorecon`, `semanage` или установки SELinux-политики. Прямая Fedora-зависимость от `libselinux` присутствует в lock и RPM payload офлайн-комплекта, а применение политик на Fedora нужно проверить фактической установкой. [Состав RPM-комплекта](../../packaging/vpn-bundle/SOURCES.md)

## Указатель Fedora-привязок

| Путь | Привязка |
|---|---|
| `install/install.sh`, `modules/pm.sh`, `modules/pm/dnf.sh`, `modules/deps.sh` | Bootstrap, выбор менеджера, RPM-имена, `/etc/yum.repos.d`, dnf4/dnf5 plugins, COPR, Terra, Matugen release fallback. |
| `install/modules/ui.sh`, `telemetry.sh` | `/etc/os-release` используется для имени системы, провайдера установки не выбирает. |
| `install/modules/verify.sh` | RPM-проверка ffmpeg-free, сообщения про COPR `hyprland-guiutils` и Terra для Mango. |
| `install/modules/vpn.sh`, `packaging/vpn-bundle/`, `vpn-bundle/`, `install/system/vpn/` | Разветвление по Fedora, ожидания RPM/DNF5, офлайн-зависимости и тексты polkit. |
| `src/scripts/system/serp_vpn{,_packages,_singbox}.py` | One-click DNF5, Fedora имена iproute/PyYAML, сообщения об обновлении движка и ожидании установки. |
| `compositors/hyprland/config/autostart.lua`, `src/scripts/system/serp_diag.py` | Polkit-путь, RPM-пробы, набор путей Qt, включая Arch и Fedora. |
| `src/scripts/system/serp_pty.py`, `src/quickshell/widgets/faces/terminal/Terminal{Core,Face,StyledFace}.qml` | DNF-подсказки, демонстрационный вывод Fastfetch с текстом «Fedora Linux». |
| `src/quickshell/guide/wallpaper/search/SearchSettings.qml`, `src/scripts/themess/themess.py` | Совет установить ffmpeg-free или подключить RPM Fusion. |
| `src/scripts/system/gpu_compatibility.py`, `src/quickshell/guide/display/DisplayGpuTab.qml` | Упоминания Fedora в текстах диагностики на другой ОС. Сами пробы используют Linux DRM и доступные программы. |
