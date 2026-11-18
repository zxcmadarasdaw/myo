# Аудит оригинального установщика Serpantinum

Аудит проведён 18 ноября 2026 года. Оригинал — [ilyamiro/serpantinum, коммит 57ab121b80358b4bd51bc0d49ecef40a6003d6db][commit], версия `2.5.1`. Коммит получен с GitHub в отдельный неглубокий checkout. Его дерево содержит 1019 файлов. Для каждого из 1019 файлов переданного ZIP рассчитан Git blob ID и подтверждено совпадение с деревом коммита. SHA-256 ZIP — `25c56ac32da2b3dbf6c271da4dbf0a4e2ec4657e17b45a860fb6170e517c2d9d`. База сравнения нашей ветки — `36461bb`.

## Структура и запуск

- `install/get.sh` скачивает bootstrap. `install/install.sh` подготавливает Git и рабочую копию, подключает Bash-модули, запускает терминальный мастер, затем зависимости, дополнительные движки, развёртывание, SDDM, службы и запись состояния. Bootstrap может вызвать пакетный менеджер до экрана выбора. [Bootstrap][get] · [Главный скрипт][install]
- `install/modules/pm.sh` выбирает адаптер pacman, DNF или XBPS. Список поддерживаемых ID и проверка ОС находятся отдельно в `deps.sh`. Выбранные композиторы добавляются как пакеты к общей группе оболочки. `quickshell` — обязательная зависимость с отдельной проверкой минимальной версии. [Выбор адаптера][pm] · [Проверка ОС и пакеты][deps] · [План зависимостей][targets]
- `compositors/` содержит конфигурации композиторов. `src/quickshell/` — оболочка, `src/scripts/` — интеграция с окружением, `bin/` — команды запуска и надзор за процессом оболочки. Скрипты Ski, Audio, Gamma и Core обслуживают дополнительные бинарники, выпуск или сборку. [Композиторы][compositors] · [Точка входа демона][daemon] · [Модули установки][modules]
- `packaging/aur/` и `nix/` дают отдельные способы установки. В стабильном PKGBUILD есть суммы архивов, в VCS-варианте Git-источник следует за веткой. Nix экспортирует пакет, приложения, Home Manager и модуль NixOS. `website/` содержит сайт документации. [Стабильный PKGBUILD][aur] · [VCS PKGBUILD][aur-git] · [Flake][flake]

## Транзакции и восстановление

| Область | Поведение в исходниках |
| --- | --- |
| pacman | Проверяет отсутствующие пакеты через `-T` и наличие в репозитории через `-Si`. Устанавливает отдельными командами, для внешнего источника использует yay/paru. Может включить multilib, выполнить `-Sy` и обновить всю систему при первой установке. Использует системное скачивание, кэш и политику доверия pacman. [Адаптер][pacman] |
| DNF | Сопоставляет имена RPM, группирует часть целей, при необходимости подключает конкретные COPR. Matugen и Satty могут устанавливаться из GitHub-релиза. Для MangoWC предусмотрен Terra с legacy-установкой `terra-release` через `--nogpgcheck`. [Адаптер][dnf] |
| XBPS | Поддерживает пакетные группы, алиасы и внешнюю ветку для Hyprland. Настройка runit/elogind и Wayland SDDM находится в отдельном адаптере. [Адаптер][void] |
| Ошибки и журнал | Ошибки отдельных целей пополняют `FAILED_PKGS`. Главный скрипт продолжает развёртывание и пишет версию, а экран завершения отдельно показывает неудачные пакеты. Формализованных фаз с повтором, отдельного отчёта о проверке архивов и сохранённой очереди в этом Bash-пути нет. [Пакеты][targets] · [Завершение][finish] · [Экран в TUI][completion] |
| Проверка целостности | Для системных пакетов используется проверка пакетным менеджером. Некоторые отдельные движки независимо сверяют опубликованный SHA-256. Общего подтверждения согласованности оболочки, QML-типов и записи сессии после развёртывания в основном скрипте нет. [Gamma][gamma] · [Завершение][finish] |
| Резервирование | Есть резервные копии конфигов композиторов и конфигурации SDDM. Состояние версии помогает отличить чистую и существующую установку. Снимок настроек с возвратом к безопасной фазе мастера в оригинале не найден. [Развёртывание][deploy] · [Состояние][state] |
| Дисплейный менеджер | Оригинал различает systemd и другие init, настраивает SDDM X11/Wayland и пользовательские службы. Для systemd есть ветка немедленного `enable --now sddm.service`. Установщик настраивает системные службы, а за процессами оболочки следит отдельный `serpantinumd`. [SDDM][sddm] · [Службы][services] · [Надзор][daemon] |

В стабильном и VCS PKGBUILD указано `AGPL-3.0-only`, в дереве есть [LICENSE.md][license]. Из внешнего checkout исходники в нашу ветку не переносились. Ссылки в отчётах указывают на конкретный коммит оригинала.

[Матрица систем](DISTRIBUTION_SUPPORT.md) · [Сравнение](INSTALLER_COMPARISON.md) · [Ошибки](BUGS_FOUND.md) · [Изменения](IMPROVEMENTS.md) · [Проверки](TEST_RESULTS.md)

[commit]: https://github.com/ilyamiro/serpantinum/commit/57ab121b80358b4bd51bc0d49ecef40a6003d6db
[get]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/get.sh
[install]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/install.sh
[pm]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules/pm.sh#L5
[deps]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules/deps.sh#L3
[targets]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules/deps.sh#L229
[compositors]: https://github.com/ilyamiro/serpantinum/tree/57ab121b80358b4bd51bc0d49ecef40a6003d6db/compositors
[modules]: https://github.com/ilyamiro/serpantinum/tree/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules
[daemon]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/bin/serpantinumd#L194
[aur]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/packaging/aur/serpantinum/PKGBUILD
[aur-git]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/packaging/aur/serpantinum-git/PKGBUILD
[flake]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/flake.nix
[pacman]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules/pm/pacman.sh
[dnf]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules/pm/dnf.sh
[void]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules/pm/void.sh
[finish]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/install.sh#L104
[completion]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules/ui.sh#L667
[gamma]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules/gamma.sh#L15
[deploy]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules/deploy.sh#L369
[state]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules/state.sh
[sddm]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules/deploy.sh#L176
[services]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules/service.sh
[license]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/LICENSE.md
