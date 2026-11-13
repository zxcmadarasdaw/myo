# Serpantinum — Music Widget & Audio Studio 2.0

Дата: 13 ноября 2026. Рабочая папка: `E:\Serpantinum`. Исходное рабочее дерево было чистым. Изменения оставлены в рабочем дереве, без коммита и установки на Fedora.

## Результат

Обновлён существующий музыкальный интерфейс. Все настольные музыкальные варианты получают отключаемую полоску Audio Studio. Она загружает прежний `MusicPopup` в новом режиме компоновки, оставляя компактный плеер видимым. Сохранены первоначальная панель, её страницы Audio/Lyrics, четыре старых варианта и старые визуализаторы. Добавлены шесть компактных вариантов и единое подтверждаемое управление существующим `serpantinum-audio`.

Инструкция пользователя, описание хранения и подробная проверка Fedora: [docs/configure/music-studio.md](../docs/configure/music-studio.md).

## Аудит до изменений

| Область | Найденный код / вывод |
| --- | --- |
| Настольная музыка | `widgets/faces/music/MusicFace.qml`, `MusicFaceRound.qml`, `MusicFaceLyrics.qml`, `MusicFaceLyricsSimple.qml`; регистрация в WidgetRegistry |
| Музыка на панели | `bar/faces/media/MediaFace.qml`; отдельный hover/popout `popouts/SideMusicPopout.qml` и `SideMusicController` |
| Дополнительная панель | `media/MusicPopup.qml`, зарегистрирована как `music` в `WindowRegistry.js` (625×565). Состав: MusicPlayerState → MusicEqualizerState, MusicCover, MusicTrackControls, MusicBottomHeader, MusicEqView, MusicAudioView, MusicLyricsView |
| Открытие панели | `serpantinum msg toggle music`, Super+M в поставляемых конфигурациях композиторов, клики MediaFace. У настольных music faces перехода к ней не было. Это установленная причина отсутствия доступа **из настольного виджета**; наличие конкретного хоткея/модуля на Fedora здесь не проверялось |
| MPRIS | `singletons/audio/MprisController.qml` и MusicPlayerState; автоопределение, поиск обложки через `media/art_fetch.sh`. В глобальном контроллере ошибочно использовался `busName`; исправлено на `dbusName` |
| Громкость/устройства | `singletons/audio/Audio.qml`: `Quickshell.Services.Pipewire`, defaultSink, setVolume, toggleMute, выбор устройств. Нового WirePlumber-демона нет |
| EQ/обработка | `media/equalizer.sh` передавал `serpantinum-audio ctl set`. Движок уже предусмотрен в `install/modules/audio.sh`, `nix/audio.nix`, `bin/serpantinumd`; его исходники/бинарник в этом checkout отсутствуют. По UI одному нельзя подтвердить DSP |
| Неподтверждённые изменения | Старый `set_band` записывал pending, а звук изменялся только после Apply. Пресеты/аудиоконтролы оптимистично меняли UI и состояние до результата `ctl`; ошибки процесса скрывались. Параллельные read-modify-write могли терять изменения |
| Спектр | `singletons/audio/Spectrum.qml` → `serpantinum-audio visualizer`; `reusables/media/Visualizer.qml`, widget `VisualizerFace`/`VisualizerFaceContinuous`, шейдеры bars/wave/ring. Реальный источник уже существовал |
| Анимации | Qt Quick Behavior/NumberAnimation, обложки, интро/аутро и EQ lightning в MusicPopup. Отдельного общего внешнего motion-runtime нет. Новые переходы используют тот же Qt Quick и профиль GpuCompatibility |
| Сохранение | Config, WidgetSync/WidgetLoader, per-monitor layouts; аудио — runtime eq_state и daemon audio.state. Themess — строгая схема JSON, варианты из WidgetRegistry |

## Существенные изменения поведения

- EQ стал live: отдельные полосы и Bass/Mid/Treble действительно посылают параметры существующему процессору. Закрытие панели не откатывает подтверждённые настройки. Старый staged Apply заменён подтверждением результата команды.
- MusicEffects сериализует команды и объединяет движения одного ползунка. Python-адаптер использует argv, общий файловый lock, проверку значений, тайм-аут и атомарные файлы. Неуспешный `ctl` не записывает успешное состояние. Старый неподтверждённый pending не мигрирует как применённый звук.
- Effects off отправляет нейтральную обработку и сохраняет желаемую кривую. Движок/маршрутизация при этом не перезапускаются. Flat/Bass/Treble/Vocal/Pop/Rock/Jazz/Classic сохранены, добавлены Bass Boost/Electronic/Cinema и именованные пользовательские пресеты.
- Volume/Mute используют прежний Audio singleton; Balance — прежний параметр аудиодвижка. Dynamic EQ и старые mono/swap/dynamics сохранены.
- Выбор Auto/плеера доступен в новых faces и Audio Studio; отсутствующие MPRIS-функции отключаются. Выбор сохраняется через Config.
- Drawer вычисляет безопасную сторону и размеры, анимация не записывает координаты виджета. Маленькая панель прокручивается, большой виджет остаётся на месте; учитываются экранные координаты canvas и монитор.
- Themess разрешает только новые параметры оформления музыки; звук, команды и QML-код из темы не принимаются.

Новые зависимости не устанавливались, системные аудиоконфигурации не изменялись, PipeWire не перезапускался. Штатный `serpantinumd` и его прежняя миграция EasyEffects не изменены.

## Проверки

| Проверка | Результат |
| --- | --- |
| `music_effects_test.py` | 15/15: миграция, десять полос всех пресетов, тональные группы, баланс, bypass, все прежние параметры протокола, persistence, исключение pending, тайм-аут/отказ, недопустимые аргументы. Транспорт подменён; звука тест не измеряет |
| `music_themess_test.py` | 2/2: варианты и параметры оформления сохраняются, аудио/команды/обработчики отклоняются |
| `music_qml_test.py` | 53 проверки Qt: шесть вариантов, минимальный размер, вызовы Play/Pause/Next/Previous тестового MPRIS, выбор/закрытие плееров, метаданные/обложка, блокировки, команды EQ/Mid, Spectrum subscriptions, материалы, missing-device UI; реальный MusicEffects и старый MusicEqualizerState проверены на очередь, отсутствие оптимистичного успеха и ошибки |
| `music_drawer_test.cjs` | 8 геометрий + проверки промежуточных кадров, выбора вверх/вниз и неизменности исходных координат |
| Qt QML parser | 26 изменённых/новых QML-файлов, 0 ошибок синтаксиса |
| `qml_imports_test.py` | PASS, включая реальную Qt remote-loading регрессию `WallpaperGif is not a type` |
| `widget_extensions_qml_test.py` | PASS: Network Monitor 6 вариантов, File Dock 6, Terminal 5 + live protocol, Process Explorer hotkey cases |
| `gpu_qml_test.py` | PASS: GPU profile/fallback, аппаратные изменения, сохранение прочих настроек |
| `wallpaper_qml_test.py` | PASS: специальные символы в путях, GIF playback/ошибки |
| `themess_test.py` | 17 тестов: 16 passed, 1 skipped по ограничению среды |
| `bash -n media/equalizer.sh`, `git diff --check` | PASS |

В Qt-тестах используются реальные файлы интерфейса и контроллеров, но Quickshell transport, аудиоустройства и материалы заменены тестовыми объектами. Рендеры в [music-studio](music-studio/) — локальные тестовые иллюстрации, не скриншоты Fedora. Исправлены обнаруженные проверками конфликт FINAL-property у Slider, объединение numeric/string аргументов drag-команд, распределение EQ-полос и минимальная высота компактного плеера.

Погодные компоненты и анимации, часы, wallpaper-компоненты, canvas, GPU singleton, Window Layouts, старые визуализаторы и Super+H не изменены. Для прочих типов виджетов добавочный размер в Widget равен нулю. Это проверка области diff, а не утверждение о полном визуальном регрессе всех функций на Linux.

## Что ещё требует Fedora

Не выполнены: полноценный запуск всей оболочки Quickshell **0.3.2**, layer-shell focus/клики/выдвижение на Hyprland, несколько мониторов/DPI/Canvas, реальный Spotify/browser/local-player D-Bus, фактическая частотная характеристика DSP, маршрутизация отдельных приложений, физическое отключение устройства, звуковая проверка после reboot, аппаратные glass/shader эффекты и весь ручной регресс оболочки. Для них подготовлен пошаговый чек-лист в инструкции. Нельзя считать mock/Qt-проверки доказательством изменения реального звука.

API MPRIS сверялся с [официальной документацией Quickshell v0.3.0](https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Mpris/MprisPlayer/): `dbusName`, capability flags и supported flags. Передача раздельных аргументов — [Process API](https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/Process/). Совместимость всего проекта с целевой 0.3.2 требует запуска на Fedora.

## Изменённые и добавленные файлы

Список ниже включает исходники, тесты и документацию; PNG тестового рендера перечислены одной папкой.

- `docs/components/serpantinum-audio.md`
- `docs/configure/music-studio.md`
- `install/tests/music_drawer_test.cjs`
- `install/tests/music_effects_test.py`
- `install/tests/music_qml_test.py`
- `install/tests/music_themess_test.py`
- `reports/MUSIC_STUDIO_REPORT.md`
- `src/quickshell/media/AudioStudioView.qml`
- `src/quickshell/media/MusicAudioView.qml`
- `src/quickshell/media/MusicBottomHeader.qml`
- `src/quickshell/media/MusicEqView.qml`
- `src/quickshell/media/MusicEqualizerState.qml`
- `src/quickshell/media/MusicPopup.qml`
- `src/quickshell/media/MusicPresetButton.qml`
- `src/quickshell/media/StudioButton.qml`
- `src/quickshell/media/StudioComboBox.qml`
- `src/quickshell/media/StudioSlider.qml`
- `src/quickshell/media/equalizer.py`
- `src/quickshell/media/equalizer.sh`
- `src/quickshell/media/qmldir`
- `src/quickshell/qmldir`
- `src/quickshell/singletons/audio/MprisController.qml`
- `src/quickshell/singletons/audio/MusicEffects.qml`
- `src/quickshell/widgets/MusicDrawerGeometry.js`
- `src/quickshell/widgets/MusicWidgetDrawer.qml`
- `src/quickshell/widgets/Widget.qml`
- `src/quickshell/widgets/WidgetRegistry.qml`
- `src/quickshell/widgets/faces/music/MusicFace.qml`
- `src/quickshell/widgets/faces/music/MusicFaceAlbumCover.qml`
- `src/quickshell/widgets/faces/music/MusicFaceCompactGlass.qml`
- `src/quickshell/widgets/faces/music/MusicFaceFloatingPlayer.qml`
- `src/quickshell/widgets/faces/music/MusicFaceLyrics.qml`
- `src/quickshell/widgets/faces/music/MusicFaceLyricsSimple.qml`
- `src/quickshell/widgets/faces/music/MusicFaceMinimal.qml`
- `src/quickshell/widgets/faces/music/MusicFaceNeonMusic.qml`
- `src/quickshell/widgets/faces/music/MusicFaceRound.qml`
- `src/quickshell/widgets/faces/music/MusicFaceStudio.qml`
- `src/quickshell/widgets/faces/music/MusicFaceVinyl.qml`
- `src/quickshell/widgets/faces/music/qmldir`
- `src/quickshell/widgets/qmldir`
- `src/scripts/themess/schema.py`
- `reports/music-studio/*.png` — 12 тестовых Qt-рендеров.

