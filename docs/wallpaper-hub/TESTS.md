# Проверки

## Этап 1 — проверки 2026-11-17

Windows, Python 3.12.10, OpenSSL 3.0.16, Qt/PySide6 6.12.0 и ffmpeg/ffprobe. Для прямых прогонов использовались временные `XDG_CONFIG_HOME`, `QS_STATE_DIR` и `QS_CACHE_DIR` без ключей. Тесты Qt заменяли Quickshell и вызов штатной установки обоев стендом.

| Команда из корня проекта | Результат |
|---|---|
| `python install/tests/wallhub_sources_test.py` | 20/20, включая изоляцию сбоя, независимые страницы, разрешение, проверку GIF/видеоверсий и отказ загрузки невалидных данных. |
| `python install/tests/wallpaper_search_live_test.py --fixtures` | 16 проверок прошли. Три MP4-плеера в Gallery, освобождение при перелистывании и закрытии Cinema, фокус, импорт, локальный поиск, избранное, офлайн, вызов Apply в стенде. |
| `python install/tests/wallpaper_search_live_test.py --live-images` | 7 проверок прошли. 25 изображений при строгом 1440p, открытие превью и скачивание оригинала. |
| `python install/tests/wallpaper_search_live_test.py --live-video` | 7 проверок прошли. Настроенный прямой MP4 960×540 H.264/AAC проигрался без звука, скачался и передан в Apply стенда. Сценарий проверяет источник Custom URLs. |
| `python install/tests/wallpaper_qml_test.py` | Прошёл. Qt загрузил PNG, GIF и анимированный WebP. Повреждённый GIF вернул ошибку, обычный WebP остался статичным. |
| `python install/tests/wallpaper_audio_qml_test.py` | Прошёл. H.264/AAC и VP9/Opus, управление, сохранение настроек и симуляция PipeWire. |
| `python install/tests/desktop_input_qml_test.py` | 0 ошибок Qt. Моделируемые поверхности ввода освобождаются при закрытии. |

### Штатный CLI с реальной сетью

| Запрос и настройка | Наблюдение |
|---|---|
| `anime girl black` · Video · 4K · Safe · без ключей | Среди сетевых источников запущен только Sepia. 0 записей из-за `certificate has expired`. Video · Any дал ту же ошибку. |
| `nature cinematic background` · Video · Any · Safe · Newest | Сетевых адаптеров нет. Sepia пропущен по сортировке, Commons по Safe Search. |
| `nature cinematic background` · Video · 1080p · Safe · Sepia | Та же ошибка TLS. |
| `nature cinematic background` · Video · Any · Safe off · Commons | Та же ошибка TLS на первой и второй страницах. |
| `anime girl black` · Images · 1080p · Safe | Wallhaven 24, Openverse 5, у всех известны размеры и есть прямые ссылки. |
| `BMW night` · Images · Any · Safe | Wallhaven 24, Openverse HTTP 504. Ошибка Openverse не остановила выдачу Wallhaven. |
| `cat animation` · Animated · Any · Openverse · Safe | 13 подтверждённых GIF из 20, 7 отброшены как неподтверждённые. |
| `cat animation` · Animated · Any · Commons · Safe off | Ошибка TLS в штатном Python-клиенте. |

### Те же запросы API через Windows curl

Проверка TLS оставалась включённой. В диагностическом процессе подменялся только транспорт получения JSON. Исходные функции адаптеров и `guard` разбирали ответы. Эти проверки подтверждают ответы API и маппинг с доступным транспортом.

- Sepia, `anime girl black` и `nature`, первая страница. По 24 записи с `nsfw=false` и длительностью. После маппинга у всех неизвестное разрешение и нет прямых ссылок или видеопревью. При Any остаются все 24. При строгом 1080p или 4K остаётся 0. При тех же порогах с включёнными неизвестными размерами остаются 24. Детали двух страниц по `nature` вернули `downloadEnabled=true`, публичные MP4 1280×720 и 640×360, а одна также вернула аудиоверсию с `hasVideo=false`.
- Commons, `city night timelapse`, Video. 12 записей с прямым WebM, известными размерами и длительностью, 11 с уменьшенным превью. При 1080p прошло 10, при 4K — 4. Для одной пары оригинал/превью HEAD подтвердил HTTP 200, `video/webm` и поддержку байтовых диапазонов. Размеры по Content-Length — 1 174 720 359 и 17 011 211 байт. Тела файлов не скачивались.
- Commons, тот же запрос в All. 14 записей от API, 13 прошли нормализацию, включая изображения и WebM. `imageinfo` не предоставил уменьшенные видео. Ogg получил подходящую версию только в Video через `videoinfo`.
- Commons, `nature`, Video, страницы 1–2. По 24 прямых WebM. Получены `continue.gsroffset` 24 и 48. Запрос второй страницы с offset 24 вернул следующий набор.

### Воспроизведение на Fedora

Из корня репозитория в Bash, с обычным системным хранилищем CA. Команды создают временные каталоги без пользовательских ключей и истории.

```bash
audit_dir=$(mktemp -d)
export XDG_CONFIG_HOME="$audit_dir/config" QS_STATE_DIR="$audit_dir/state" QS_CACHE_DIR="$audit_dir/cache"
hub=src/scripts/wallpaper/wallhub.py
python3 "$hub" search --query 'anime girl black' --kind video --min 4k --include-unknown --translate off
python3 "$hub" search --query 'anime girl black' --kind video --min 4k --translate off
python3 "$hub" search --query 'city night timelapse' --sources commons --kind video --min any --unsafe --translate off
python3 "$hub" search --query nature --sources commons --kind video --page 2 --unsafe --translate off
python3 "$hub" search --query 'cat animation' --sources openverse --kind animated --min any --translate off
python3 install/tests/wallhub_sources_test.py
```

В JSON Lines сверить `start.sources`, `source.status.error`, `received`, `hidden`, `count`, `hasMore` и поля отдельных записей. В настоящем сеансе открыть Super+H и сравнить фильтры с CLI. Целевой Fedora 45 / Hyprland / Quickshell в этой среде недоступен. На нём ещё предстоит проверить поиск штатным Python, декодирование и переходы при Apply.

## История предыдущей задачи

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
