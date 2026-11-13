---
title: Fedora — проверка, обновление и восстановление
sidebar_label: Fedora: диагностика
---

# Serpantinum на Fedora: проверка, обновление, диагностика

Документ описывает проверки, которые нужно выполнить **на реальной Fedora 45 + Hyprland**.
Исправления подготовлены и проверены на Windows (парсер QML, Qt offscreen, bash-тесты
с заглушками). Запуск в настоящей сессии Wayland/Hyprland там не выполнялся.

## 1. Обновление уже установленного Serpantinum

Установщик теперь при каждом запуске полностью копирует `bin/`, `src/` и `themess/`
в `~/.local/share/serpantinum`, в том числе незакоммиченные правки.

```bash
cd ~/путь/к/Serpantinum
bash install/install.sh
```

Конфигурация Hyprland (`~/.config/hypr`) при обычном обновлении **не перезаписывается**.
Чтобы получить исправленный автозапуск и аварийные хоткеи, выберите в установщике
переустановку или скопируйте три файла вручную, предварительно сделав резервную копию:

```bash
cp -a ~/.config/hypr ~/.config/hypr_backup_$(date +%Y%m%d_%H%M%S)
```

```bash
cp compositors/hyprland/config/{autostart,env,keybinds}.lua ~/.config/hypr/config/
```

Итог установки теперь честный: при отсутствии обязательных компонентов выводится
`was NOT installed completely` со списком ошибок, а код выхода равен 1.

## 2. Проверка окружения после установки

```bash
quickshell --version
```

```bash
Hyprland --version
```

Lua-конфигурацию (`hyprland.lua`) читает только Hyprland версии **0.55 и новее**. Более
старая версия запускается с автоматически созданным конфигом: без автозапуска, то есть
без оболочки и обоев. Установщик проверяет это и пытается обновить Hyprland из COPR.

```bash
rpm -q quickshell qt6-qtmultimedia qt6-qtwayland qt6-qtimageformats qt6-qtdeclarative kitty jq python3
```

`qt6-qtimageformats` обязателен: без него Qt не открывает обои в формате **WebP**,
а такие файлы есть в загружаемом наборе обоев.

Terra нужен **только для MangoWC** (пакет `mangowm`). Hyprland, Quickshell и
оболочка от него не зависят. Если Terra уже подключён в системе (`terra-release`
остался от прошлой установки MangoWC) и недоступен, dnf прерывал всю установку.
Теперь установщик отключает репозитории `terra*` (`--disablerepo`) во всех вызовах
dnf, кроме установки `mangowm`. Если Terra не удаётся подключить при выборе Mango,
установка `mangowm` помечается как неудачная, остальные пакеты ставятся.

Проверить, подключён ли Terra:

```bash
rpm -q terra-release; ls /etc/yum.repos.d/ | grep -i terra
```

Если Mango больше не нужен, Terra можно удалить: `sudo dnf remove terra-release`.

## 3. Автоматические тесты

На Fedora (из корня репозитория):

```bash
bash install/tests/install_runtime_test.sh
```

На Linux этот тест также проверяет надзор `serpantinumd` (лог, 3 повтора, аварийный режим).

```bash
python3 install/tests/themess_test.py
```

```bash
python3 install/tests/gpu_compatibility_test.py
```

Тесты с Qt требуют PySide6 (`pip install --user PySide6`):

```bash
python3 install/tests/wallpaper_qml_test.py
```

```bash
python3 install/tests/themess_qml_test.py
```

```bash
python3 install/tests/apptheme_test.py
```

`apptheme_test.py` работает только на Linux (использует `fcntl`).

## 4. Ручная проверка в сессии Hyprland

1. Войти в сессию Hyprland. Должны появиться панель и обои.
2. `serpantinum logs` — в логе строка `starting quickshell ...` и нет повторных `exited with code`.
3. Super+W — выбрать JPG, PNG, WebP, GIF (GIF должен анимироваться) и WebM.
4. `serpantinum restart` — обои восстанавливаются.
5. Подключить второй монитор — на нём появляются те же обои, а не пустой фон.
6. Super+H → Themess — применить пакет MrRobot; обои меняются, «Восстановить» возвращает прежние.
7. Включить «Performance mode» — обои остаются, переходы и видео становятся статичными.

## 5. Если обои не загружаются

```bash
serpantinum logs 200
```

Ищите строки `[wallpaper]`. Теперь при ошибке на экране показывается причина,
фон остаётся тёмным, а оболочка продолжает работать.

```bash
ls -la ~/.cache/serpantinum/wallpaper/
```

Файлы `current_<монитор>` содержат абсолютный путь к выбранным обоям. Проверьте, что файл существует и читается:

```bash
for f in ~/.cache/serpantinum/wallpaper/current_*; do case "$f" in *_name|*.png) continue;; esac; p="$(cat "$f")"; echo "$f -> $p"; ls -la "$p"; done
```

Типичные причины:

| Симптом | Причина | Решение |
|---|---|---|
| WebP не открывается | нет плагина Qt | `sudo dnf install qt6-qtimageformats` |
| MP4/MOV — ошибка видео | `ffmpeg-free` без H.264/HEVC | WebM (VP9/AV1) или `ffmpeg` из RPM Fusion |
| Папка обоев пуста | не скачался набор обоев | первый запуск берёт обои из `themess/*/wallpapers`; добавьте свои в `~/Pictures/Wallpapers` |
| Обоев нет совсем | старый Hyprland не прочитал `hyprland.lua` | см. раздел 2 |
| Нет обоев на новом мониторе | у монитора нет сохранённого файла | теперь берутся обои соседнего монитора |

Сбросить выбор обоев:

```bash
rm -f ~/.cache/serpantinum/wallpaper/current_*
```

```bash
serpantinum restart
```

## 6. Если после входа пустой рабочий стол

Хоткеи, которые работают без оболочки:

- **Super+Return** — терминал (kitty);
- **Super+Ctrl+R** — перезапуск оболочки (`serpantinum restart`);
- **Super+Ctrl+Shift+Escape** — выход из сессии (если ваша версия Hyprland поддерживает `hl.dsp.exit`);
- **Super+M** — встроенный аварийный выход Hyprland, если в конфиге ошибка.

Если оболочка трижды подряд падает при запуске, `serpantinumd` показывает
уведомление и сам открывает терминал с концом лога.

```bash
serpantinum logs 200
```

```bash
serpantinumd status
```

```bash
command -v serpantinumd quickshell
```

```bash
hyprctl configerrors
```

Запуск оболочки вручную с выводом ошибок QML в терминал:

```bash
serpantinumd stop
```

```bash
quickshell -p ~/.local/share/serpantinum/src/quickshell/Shell.qml
```

Сообщения `module "..." is not installed` означают отсутствующий QML-модуль: обычно
`qt6-qtmultimedia`, `qt6-qtdeclarative` или устаревший `quickshell`.

## 7. Восстановление рабочего окружения

1. Переключитесь в TTY (Ctrl+Alt+F3) или войдите в другую сессию (установщик не трогает KDE Plasma).
2. Верните прежний конфиг Hyprland — резервные копии лежат в `~/.config/hypr_backup/`:

```bash
ls ~/.config/hypr_backup/
```

```bash
cp -a ~/.config/hypr_backup/backup_ДАТА/. ~/.config/hypr/
```

3. Повреждённые настройки: оболочка запускается с настройками по умолчанию и сохраняет
   копию испорченного файла как `~/.config/serpantinum/settings.json.corrupt`.
4. Откат Themess: Super+H → Themess → «Восстановить исходное».
5. Полная переустановка: `bash install/install.sh` и выбор переустановки.
