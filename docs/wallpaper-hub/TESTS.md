# Проверки

## Исходное состояние на Windows

Проверки вызвали текущий CLI с пустым временным хранилищем ключей.

| Запрос | Фильтр | Факт |
|---|---|---|
| anime girl black | Images · 1080p · Safe | 24 Wallhaven + 5 Openverse |
| anime girl black | Video · 4K · Safe | 0 активных источников |
| anime girl animated wallpaper | Animated · Any · Safe | 0 из Openverse, Giphy требует ключ |
| cyberpunk animated background | Video · Any · Safe off | Commons ответил ошибкой TLS «certificate has expired» |
| BMW night driving wallpaper | Video · 4K · Safe off | Та же ошибка TLS у Commons |
| anime girl live wallpaper mp4 | Video · Any · Safe | 0 активных источников |

`wallhub_sources_test.py` — 8 тестов прошли. `wallpaper_qml_test.py` — загрузка PNG и анимация GIF прошли. PySide6 6.12.0 и ffmpeg/ffprobe доступны. WSL в этой среде не установлен, целевой сеанс Fedora/Hyprland недоступен.

## Итоговые проверки на Windows

| Сценарий | Фактический результат |
|---|---|
| A — Images | `--live-images` через настоящий QML и реальные API нашёл 25 изображений по `anime girl white` при строгом фильтре 1440p. Отображение превью, переход на соседний результат и скачивание оригинала проверены. Отдельный CLI-запуск загрузил JPEG 3840×2160 с Wallhaven. |
| B — Videos | Реальный поиск `anime girl black · Video · 4K` и `anime girl live wallpaper` не подтвердился. Sepia и Commons вернули ошибку проверки сертификата. Brave, Pexels и Pixabay были пропущены из-за отсутствия ключей. Публичный MP4 960×540 H.264 найден через пользовательский источник и воспроизведён по сети без звука. Отдельно QML воспроизвёл три MP4-превью, переключение и выгрузка плееров проверены. |
| C — Animated | `anime girl animated` вернул 0 из Openverse, Brave и GIPHY требуют ключи. По `cat animation` второй живой запрос нашёл 13 проверенных GIF из 20 кандидатов, один оригинал скачан и измерен как GIF с 45 кадрами. Движение GIF и WebP прогнано в Qt. APNG проверен импортом и фактической конвертацией в WebM через ffmpeg. |
| D — Широкий поиск | Реальный `BMW M5 night rain` вернул 2 из Openverse. Параметры обоих API Brave проверены подставными структурированными ответами. Живой ответ Brave не проверен без пользовательского ключа. |
| E — All Sources | Два живых каталога дали результаты для Images. Отдельный тест провёл успешную и ошибочную ветки в одном параллельном вызове и проверил независимые страницы. |
| F — офлайн | Стенд QML подал сетевое событие об ошибке. Библиотека осталась доступна, новых вызовов установки не было. |
| G — Apply | Реальные MP4 прошли оба пути, сетевую загрузку и локальный импорт. Проверены запись в библиотеку и передача файла через `Wallpaper.setWallpaper` в стенде. Фоновый рендеринг Fedora и сохранение после перезапуска Quickshell не проверены. |

- `python install/tests/wallhub_sources_test.py` — 20 тестов.
- `python install/tests/wallpaper_search_live_test.py --fixtures` — Qt с заменой Quickshell и сетевой выдачи для видео, реальные процессы импорта и локального поиска, проверка фокуса и избранного.
- `python install/tests/wallpaper_search_live_test.py --live-images` — Qt и живой поиск, загрузка JPEG и измерение оригинала.
- `python install/tests/wallpaper_search_live_test.py --live-video` — реальная ссылка из пользовательского источника, удалённое воспроизведение, загрузка и Apply в стенде Qt.
- `python install/tests/wallpaper_qml_test.py` — PNG, GIF, анимированный WebP, статичный WebP и восстановление после битого GIF.
- `python install/tests/wallpaper_audio_qml_test.py` — медиа, сохранение настроек, маршрутизация с подставным PipeWire.
- `python install/tests/desktop_input_qml_test.py` — Qt-проверка освобождения мыши при закрытии и быстрых переключениях.
- `git diff --check` по файлам Wallpaper Hub. AST-копия графа проверена во временном каталоге, исходный граф не использовался как место записи обновления.
