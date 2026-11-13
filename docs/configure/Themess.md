# Themess

Откройте настройки Serpantinum через **Super + H** и выберите **Themess** в боковом меню. Вкладку также можно найти через общий поиск настроек.

- **Import Folder** добавляет выбранную папку в библиотеку и показывает распознанные компоненты. **Refresh** проверяет пакеты из `themess/` рядом с кодом оболочки, `~/.local/share/serpantinum/themess/` и ранее добавленные папки.
- **View Components** показывает файлы и параметры пакета. **Preview** показывает статичную схему рабочего стола с обоями, палитрой, виджетами, материалами и списком изменений. Раскладка на схеме рассчитана для условного экрана 1600 × 900.
- **Apply** сверяет пакет и запускает существующий механизм Themess. При частичной совместимости применяются поддерживаемые компоненты. Ошибки в поддерживаемом компоненте блокируют запись. Активный пакет сохраняется между запусками.
- **Open Theme Folder** открывает исходный каталог. **Remove From Library** убирает запись о папке из библиотеки и оставляет её файлы на месте. Чтобы снова показать папку, выберите её через **Import Folder**.
- **Restore Previous** возвращает оформление перед последним Apply. **Restore Original** возвращает снимки файлов до первого изменения каждого из них в текущей серии применений. Оба действия восстанавливают содержимое затронутых файлов целиком, включая состояние `settings.json` на момент снимка. В старых установках базой для Restore Original служит последний доступный снимок предыдущей версии.

MrRobot находится в [themess/MrRobot](../../themess/MrRobot/theme.json). Виджеты заменяют раскладку экрана, на котором открыты настройки. Обои применяются на всех экранах с активным движком обоев. Infinite Desktop применяется, если в сессии доступна камера холста. В безопасном режиме графики GIF отображается статично.

Диалог выбора каталога использует стандартный `FolderDialog` с родительским окном настроек. Qt выбирает нативный диалог или свою резервную реализацию в зависимости от платформы. [Документация Qt FolderDialog](https://doc.qt.io/qt-6/qml-qtquick-dialogs-folderdialog.html)

## Обновление на Fedora 45 + Hyprland

Из корня репозитория выполните один раз в запущенной сессии Hyprland. Команды рассчитаны на стандартную установку Serpantinum в `~/.local/share/serpantinum`. Они сохраняют предыдущие файлы оболочки и пример пакета в отдельный каталог.

```bash
(
    set -eu
    app="$HOME/.local/share/serpantinum"
    state="$HOME/.local/state/serpantinum"
    test -f "$app/src/quickshell/Shell.qml"
    command -v python3
    command -v ffmpeg

    files=(
        src/quickshell/qmldir
        src/quickshell/guide/GuidePopup.qml
        src/quickshell/guide/ThemessTab.qml
        src/quickshell/guide/themess/ThemessPreview.qml
        src/quickshell/guide/wallpaper/CurrentWallpaper.qml
        src/quickshell/singletons/system/Config.qml
        src/quickshell/singletons/system/Themess.qml
        src/quickshell/singletons/theme/ThemeBackend.qml
        src/quickshell/wallpaper/WallpaperEngine.qml
        src/quickshell/wallpaper/WallpaperGif.qml
        src/quickshell/widgets/WidgetLoader.qml
        src/quickshell/widgets/WidgetRedactor.qml
        src/scripts/themess/schema.py
        src/scripts/themess/themess.py
        src/assets/languages/ru.json
        themess/MrRobot/{theme,palette,materials,panels,animations,canvas,dock,launcher,notifications,widgets}.json
        themess/MrRobot/wallpapers/mr-robot.gif
    )
    for file in "${files[@]}"; do test -f "$file"; done

    mkdir -p "$state"
    backup=$(mktemp -d "$state/themess-update.XXXXXX")
    printf '%s\n' "${files[@]}" > "$backup/files"
    for file in "${files[@]}"; do
        if [ -e "$app/$file" ] || [ -L "$app/$file" ]; then
            mkdir -p "$(dirname "$backup/previous/$file")"
            cp -a -- "$app/$file" "$backup/previous/$file"
        fi
    done
    printf 'Backup: %s\n' "$backup"

    for file in "${files[@]}"; do
        install -D -m 644 -- "$file" "$app/$file"
    done
    serpantinum reload
)
```

Для дальнейшей работы откройте Themess через **Super + H**. Применение и восстановление пакетов обновляют текущую сессию через штатные файлы Serpantinum.

### Возврат к предыдущей версии

Чтобы вернуть исходное оформление, сначала нажмите **Restore Original** в Themess. Для отката файлов программы подставьте путь `Backup`, выведенный при обновлении.

```bash
(
    set -eu
    app="$HOME/.local/share/serpantinum"
    backup="$HOME/.local/state/serpantinum/themess-update.XXXXXX"
    test -f "$backup/files"
    while IFS= read -r file; do
        if [ -e "$backup/previous/$file" ] || [ -L "$backup/previous/$file" ]; then
            mkdir -p "$(dirname "$app/$file")"
            cp -a --remove-destination -- "$backup/previous/$file" "$app/$file"
        else
            rm -f -- "$app/$file"
        fi
    done < "$backup/files"
    serpantinum reload
)
```

## Формат пакета v1

`theme.json` задаёт относительные пути к компонентам. Пример файла

```json
{
  "version": 1,
  "name": "My Desktop",
  "author": "Example author",
  "description": "A dark desktop with a compact layout.",
  "components": {
    "wallpaper": "wallpapers/night.gif",
    "palette": "palette.json",
    "widgets": "widgets.json"
  }
}
```

Поля `author` и `description` необязательны.

Видео-обои в MP4 с H.264 или HEVC на Fedora без RPM Fusion `ffmpeg` (только `ffmpeg-free`) не воспроизводятся. Для таких систем используйте WebM (VP9 или AV1): так сделаны темы Black Hole.

Если манифест отсутствует, используются имена из таблицы. Для обоев укажите ровно один файл с базовым именем `wallpaper` в корне пакета или в `wallpapers/`. Манифест имеет приоритет над файловой структурой.

| Компонент | Имя без манифеста | Данные |
| --- | --- | --- |
| `wallpaper` | `wallpaper.gif`, `wallpaper.png`, `wallpaper.jpg`, `wallpaper.jpeg`, `wallpaper.webp`, `wallpaper.mp4`, `wallpaper.webm` | Проверяемое изображение или видео с соответствующим расширением. Видео: до 24 МБ и 10 минут, не больше 4096 пикселей по стороне, кодек H.264, HEVC, VP8, VP9 или AV1, звук не используется. Файл проверяется ffprobe/ffmpeg во временной папке, пакет не получает доступа к другим путям |
| `palette` | `palette.json` | `mode` и `colors` с именами цветов Serpantinum и значениями `#RRGGBB`. При применении палитра активируется как статическая |
| `materials` | `materials.json` | Радиус скругления, непрозрачность элементов, размытие, стиль размытия и семейство шрифта |
| `panels` | `panels.json` | Положение, размер, стиль, поведение и раскладка штатных модулей панели |
| `animations` | `animations.json` | Пул и параметры переходов обоев |
| `canvas` | `canvas.json` | Глобальные параметры Infinite Desktop. Существующие настройки отдельных экранов имеют приоритет |
| `dock` | `dock.json` | Положение, размер, оформление и поведение Dock |
| `launcher` | `launcher.json` | Положение, ширина, число результатов и умное ранжирование |
| `notifications` | `notifications.json` | Позиция, координаты, режим DND, звук и параметры отображения |
| `widgets` | `widgets.json` | Массив встроенных виджетов, каждый с `id`, `type`, `x`, `y`, `w`, `h` и необязательными `variant` и `anchor` |

Полные рабочие примеры находятся в [MrRobot](../../themess/MrRobot/theme.json). Список допустимых полей и диапазонов задан в [схеме](../../src/scripts/themess/schema.py). Настройки отсутствующих компонентов и неприсланные поля сохраняются. Явный пустой массив виджетов очищает выбранную раскладку.

Неподдерживаемые компоненты отмечаются при сканировании. Ошибки в манифесте или в поддерживаемом компоненте блокируют применение. Themess принимает данные по схеме, проверяет изображения декодированием, отклоняет пути за пределы папки и символические ссылки внутри неё. Скрипты и исполняемые расширения пакетов игнорируются. Резервные копии и скопированные обои хранятся в `~/.local/state/serpantinum/themess/`. Если процесс был прерван после начала записи, следующая операция восстанавливает транзакцию по журналу.

## Проверка

```bash
python3 install/tests/themess_test.py
python3 install/tests/themess_qml_test.py
```

Первый тест использует `ffmpeg` для проверки MrRobot. Второй использует PySide6, окно Qt и заглушки Quickshell. Тест открывает FolderDialog, передаёт выбранную папку, запускает настоящий движок в отдельном профиле, проверяет предпросмотр, запись настроек, откат и удаление записи из библиотеки. Тесты запускаются от обычного пользователя.

### Проверка в запущенной сессии Fedora

```bash
hyprctl binds | grep -B 6 -A 1 -F 'serpantinum msg toggle settings'
quickshell -p "$HOME/.local/share/serpantinum/src/quickshell/Shell.qml" ipc call main embeddedSettings open themess
```

1. Закройте окно настроек. Нажмите **Super + H**, найдите Themess в боковом меню и через поиск. Переключитесь на обычные темы и обратно.
2. Нажмите **Import Folder** и выберите каталог пакета вне библиотеки. Проверьте открытие, выбор и отмену диалога в Wayland. Сверьте найденные компоненты с манифестом.
3. Откройте **Preview**. Убедитесь, что схема совпадает с данными пакета, а фон, виджеты и панели рабочего стола остались прежними.
4. Примените MrRobot. Проверьте живые обои, раскладку, панель, Dock и отмеченные совместимые компоненты. Закройте и снова откройте настройки. После `serpantinum reload` проверьте отметку активного пакета.
5. Примените второй пакет. Выполните **Restore Previous**, затем **Restore Original**. Проверьте оформление после каждого действия. Нажмите **Remove From Library** и проверьте исходную папку в файловом менеджере.
6. Добавьте новую папку пакета в `~/.local/share/serpantinum/themess/`. Нажмите **Refresh**. Импортируйте копию с повреждённым JSON и убедитесь, что причина показана в компонентах и Apply недоступна.
