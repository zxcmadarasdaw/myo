# Widget Fusion и Music Studio Pro

## Widget Fusion

В редакторе виджетов выделите два или больше элементов через **Shift+клик** и нажмите **Combine Widgets**. В секции **Fusion** доступны Unified Panel, Seamless, Modular Grid, Horizontal Stack, Vertical Stack, Freeform Fusion и Adaptive Fusion. Последний меняет число столбцов при изменении ширины. Seamless убирает зазоры и контур общей рамки. Варианты оформления меняют фон, рамку, толщину отступов и шрифт заголовка. Можно отдельно менять зазоры, число столбцов, отступы, радиус, прозрачность, разделители и появление рамки. В **Custom** доступен цвет фона `#RRGGBB`.

- Перетаскивайте любой элемент, чтобы перемещать группу. В Freeform включите **Drag one widget** для перемещения отдельного элемента. **Earlier** и **Later** меняют порядок в раскладке. В Freeform позиции задаются перетаскиванием.
- **Width** и **Height** задают размеры области раскладки. Сами виджеты учитывают собственные ограничения размера и пропорций. Элементы, растянутые на весь экран, сперва нужно перевести в фиксированный размер. Если у элемента было экранное выравнивание, Fusion переводит его в мировые координаты.
- Настраивайте виджеты через их обычные панели. Используйте штатные **Ungroup**, **Undo/Redo** и сохранение **Composition** в панели холста. Каждая повторно вставленная композиция получает отдельные ID виджетов и групп.
- Общая рамка рисуется слоем ниже рабочих виджетов. Сами виджеты сохраняют данные и маршруты ввода. Родной `layout.json` хранит позицию контейнера и смещения элементов, а также абсолютные координаты, которые понимают старые версии. Камера Infinite Canvas трансформирует рамку и виджеты вместе.

### Перенос в Themess

Закройте редактор виджетов, откройте **Super+H → Themess** на нужном мониторе и нажмите **Copy Fusion as widgets.json**. Вставьте содержимое буфера в `widgets.json` в папке темы, затем импортируйте папку. Экспорт включает Fusion-группы текущего монитора и поля оформления, разрешённые схемой Themess. Внешние файлы изображений и команды терминала в пакет не попадают. Если участник группы относится к типу, который нельзя импортировать, Themess покажет ошибку экспорта.

Формат сохраняет исходные `x`, `y`, `w`, `h` каждого элемента. Массив `groups` задаёт порядок идентификаторов, оформление и режим последующего редактирования. Исходные пакеты, где `widgets.json` содержит один массив, продолжают загружаться. Перед заменой существующей раскладки на выбранном экране Themess показывает число заменяемых виджетов. **Restore Previous** возвращает предыдущую раскладку с её группами.

```json
{
  "widgets": [
    {"id": "cpu", "type": "cpu", "x": 80, "y": 120, "w": 240, "h": 180},
    {"id": "ram", "type": "ram", "x": 332, "y": 120, "w": 240, "h": 180}
  ],
  "groups": [
    {"id": "dashboard", "members": ["cpu", "ram"], "appearance": {
      "mode": "horizontal", "style": "technical", "title": "System Dashboard",
      "gap": 12, "dividers": true, "animation": "fade"
    }}
  ]
}
```

## Music Studio Pro

Откройте **Audio Studio** в музыкальном виджете и прокрутите до **Live Remix**. График EQ показывает настройки десяти существующих полос. Bass Boost и Treble Boost используют те же полосы, ограничивают добавленный Gain диапазоном 0–4 дБ и при первом положительном усилении включают Balanced Dynamics, если динамика была выключена. Доступны Mono и три режима Dynamics. Ручные полосы и усиление недоступны, пока активен Dynamic EQ. Эффекты применяются к потокам, направленным в штатный `serpantinum_sink`.

Night Drive, Slowed, Nightcore и Deep Bass используют EQ и существующую динамику. Для собственного пресета задайте имя, при необходимости включите **Include current speed in preset** и нажмите **Save Preset**. Доступны Load, Rename, Duplicate, Delete и Reset Remix. **Original** ставит скорость 1.00× на совместимом плеере и включает bypass, сохраняя кривую. **Reset Remix** обнуляет параметры обработки и запрашивает скорость 1.00×. Пресеты записываются в `studio_remixes.json` рядом со штатным `studio.json`. Сохранённая скорость применяется при явной загрузке пресета.

В **Super+M** расположена кнопка **Speed** между отметками времени. Она открывает ползунок, точное значение, быстрые скорости 0.75×, 1.00×, 1.25×, 1.50× и сброс. Панель и Audio Studio читают `Rate` одного плеера. Выбор источника в Super+M теперь сохраняется через общий MPRIS-контроллер Serpantinum.

| Плеер | Поведение |
| --- | --- |
| MPRIS с разрешённым управлением и изменяемой `Rate` | Работает пересечение диапазона плеера с 0.50–2.00×, шаг 0.01×. |
| MPRIS с фиксированной скоростью или без права управления | Отображается значение, регулировка недоступна. |
| MPRIS объявляет диапазон, но игнорирует запись | Остаётся показанное плеером значение и появляется сообщение об отсутствии подтверждения. |
| Без MPRIS | Нет доступного регулятора скорости. EQ возможен для потока в `serpantinum_sink`. |

Стандарт MPRIS передаёт `Rate`, а обработку высоты тона выбирает сам плеер. В штатном аудиодвижке нет управляемых параметров Reverb, Delay, Stereo Width, Pitch Shift, независимого Tempo Control, Low-pass или High-pass. Qt Multimedia используется в других подсистемах проекта и не управляет темпом внешних приложений. EasyEffects может обрабатывать собственный маршрут PipeWire, но Audio Studio отправляет параметры только штатному движку Serpantinum.

## Проверка на Fedora 45

1. Перенесите изменённый checkout целиком и запустите его в отдельной Hyprland-сессии по инструкции [Music Widget + Audio Studio](../docs/configure/music-studio.md). Проверьте `python3 install/modules/qml_check.py src/quickshell`, `python3 src/quickshell/media/equalizer.py status` и `wpctl status`.
2. Откройте редактор командой `serpantinum redactor`. Сначала объедините два виджета, затем CPU/GPU/RAM/Network. Проверьте все режимы, порядок, изменение размеров, перенос группы и отдельного виджета, Undo/Redo и Ungroup. Увеличьте холст и переместите камеру. Закройте редактор, проверьте ввод и обновление данных на десктопе. Перезапустите оболочку и повторно вставьте сохранённую композицию. Экспортируйте её через Themess, импортируйте тему, примените и нажмите **Restore Previous**.
3. Проверьте локальный плеер с MPRIS, браузер и Spotify. Возможность менять скорость зависит от объявленных конкретным приложением `CanControl`, `MinimumRate`, `MaximumRate` и фактического ответа на запись `Rate`. Проверьте смену скорости на ходу, сброс, закрытие окна плеера и смену источника при открытых Audio Studio и Super+M. Проверьте старые действия Super+M, анимацию и закрытие popover мышью и клавиатурой.
4. Направьте поток плеера в `serpantinum_sink`. Включите тестовый трек на умеренной громкости. Сравните EQ и bypass, затем проверьте усиление баса, высоких, Mono, Dynamics и все операции с ремикс-пресетами. Для оценки задержки, щелчков и клиппинга запишите один и тот же сигнал до/после переключения, проверьте пики и сам переход. Проверьте оригинальный звук, сохранённую скорость и повторное открытие панели после перезапуска.
5. Повторите проверку с видеообоями, Smart Wallpaper Audio, анимированным Fastfetch, визуализатором и OBS. Следите за `pw-top`, отзывчивостью мыши и журналом оболочки. Проверьте рабочие пространства, горячие клавиши окон, Super+H, Super+N и VPN.

## Локальные проверки

```bash
node install/tests/widget_fusion_test.cjs
python3 install/tests/widget_fusion_qml_test.py
python3 install/tests/music_effects_test.py
python3 install/tests/music_qml_test.py
python3 install/tests/themess_test.py
python3 install/tests/qml_imports_test.py
python3 install/tests/desktop_input_qml_test.py
python3 install/tests/wallpaper_audio_qml_test.py
node install/tests/music_drawer_test.cjs
python3 install/tests/music_themess_test.py
python3 install/tests/widget_extensions_qml_test.py
python3 install/tests/workspace_slots_qml_test.py
python3 install/tests/fastfetch_media_qml_test.py
python3 install/tests/vpn_qml_test.py
```

Локально прошли 60 проверок музыкального QML, 18 тестов адаптера эффектов, проверки раскладок и рендеринга Fusion и 23 из 24 тестов Themess. Тест символьной ссылки пропущен из-за прав Windows. Регрессионные проверки импортов QML, ввода, аудио обоев, музыкальных виджетов, терминалов, рабочих пространств, Fastfetch и VPN также прошли.

Тесты Qt используют PySide6 и подставные интерфейсы Quickshell. На Windows проверены вычисления геометрии и сохранения, рендеринг Qt, обмен параметрами эффектов с подставным движком и транзакции Themess. Проверка системного ввода Wayland, реального MPRIS, маршрутизации PipeWire, задержки и слышимых переходов требует целевой сессии Fedora.

## Изменённые компоненты

- Fusion и Infinite Canvas — `WidgetRedactor.qml`, `WidgetLoader.qml`, `CanvasRedactorPanel.qml`, `FusionOptions.qml`, `FusionFrames.qml`, `WidgetFusion.js`, `WallpaperEngine.qml`.
- Music Studio Pro и Super+M — `AudioStudioView.qml`, `RemixStudio.qml`, `PlaybackSpeed.qml`, `MusicTrackControls.qml`, `MusicPlayerState.qml`, `MprisController.qml`, `MusicEffects.qml`, `media/qmldir`, `equalizer.py`.
- Themess — `ThemessTab.qml`, `Themess.qml`, `scripts/themess/schema.py`, `scripts/themess/themess.py`.
- Новые сценарии в `widget_fusion_test.cjs` и `widget_fusion_qml_test.py`. Дополнены тесты `music_effects_test.py`, `music_qml_test.py` и `themess_test.py`.
