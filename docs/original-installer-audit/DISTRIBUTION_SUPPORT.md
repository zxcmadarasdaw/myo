# Поддержка дистрибутивов

Оригинал зафиксирован в [57ab121b80358b4bd51bc0d49ecef40a6003d6db][commit]. Допуск ID и наличие менеджера пакетов показывают предусмотренный путь. Совместимость репозиториев, пакетов и графической сессии определяется отдельной нативной проверкой.

| Система | Определение и зависимости в оригинале | Источники и действия root | Практический статус |
| --- | --- | --- | --- |
| Arch Linux | `arch` в списке. pacman, общий набор оболочки и выбранный композитор. yay/paru при отсутствии пакета, возможна сборка yay-bin. | Системные репозитории. Возможное включение multilib, обновление базы, установка и полный upgrade через sudo. | Нативный pacman проверен на CachyOS и с официальными пакетами Arch. Отдельный чистый Arch в этом прогоне не загружался. |
| CachyOS | `cachyos` в том же списке. Отдельного адаптера у оригинала нет. | Те же операции, конфигурация и порядок зеркал задаются системой. Для Live особенно важны свободное место и согласованные базы. | Изолированная транзакция на CachyOS Live. Полная установка на физическом Live USB ещё требует проверки. |
| EndeavourOS | `endeavouros` в списке. Общий адаптер pacman. | Системные и дистрибутивные репозитории по эффективному конфигу. Внешние цели могут потребовать AUR. | Включён по ID. Нативный запуск конкретного образа не проверялся. |
| Manjaro | `manjaro` в списке. Общий адаптер pacman. | Состав и версии пакетов определяются веткой и зеркалами Manjaro. Оригинал может вызвать полный upgrade и AUR. | Включён по ID. Версии Hyprland/Quickshell и согласованность ветки проверяются на самой системе. Нативный запуск не выполнялся. |
| Fedora | ID/ID_LIKE содержит `fedora`; адаптер отклоняет OSTree, отдельные EL-варианты исключены. Алиасы RPM, Quickshell, Hyprland и дополнительные программы. | Базовые RPM, COPR при отсутствии нужного пакета, Terra для MangoWC, отдельные GitHub-релизы. sudo для DNF и подключения репозиториев. | Fedora 45 — наша целевая версия. Нативная очередь DNF5 подтверждена на подписанном RPM. Полный COPR и графический запуск не проверялись. |
| Nobara | Отдельной ветки нет. Попадает в DNF-путь при `ID_LIKE=fedora` и наличии DNF. | Те же RPM и COPR. Наличие пакета проверяется по фактически загруженным репозиториям. | Вывод по правилам кода. Отдельного нативного теста и гарантии для репозиториев нет. |
| Ultramarine | Отдельной ветки нет. Попадает в DNF-путь при `ID_LIKE=fedora` и наличии DNF. | Общий DNF-путь. Terra может быть уже настроена в системе. | Нативный тест не выполнялся. [Документация Fyra Labs о Terra в Ultramarine][terra] |
| Void Linux | XBPS и проверка Void. Алиасы пакетов, runit, elogind и Xwayland. | sudo для XBPS, внешнего репозитория Hyprland и системных служб. У отдельных тем и шрифтов есть release-варианты. | Существующий отдельный путь сохранён. Актуальные ключи, пакеты и Wayland-сессия Void нативно не проверялись. |
| NixOS | Отдельный flake, пакеты `x86_64-linux`/`aarch64-linux`, модуль NixOS и Home Manager. | Системные опции через rebuild NixOS. Пользовательская конфигурация и опциональный systemd user unit через Home Manager. | Nix-путь сохранён. Сборка и активация на NixOS не выполнялись. |

Общий набор оболочки определяет [deps.sh оригинала][deps]. Привилегированные действия прослеживаются в [pacman][pacman], [DNF][dnf], [XBPS][void] и [NixOS/Home Manager][nix]. Текущая ветка определяет провайдера до bootstrap, отклоняет OSTree и проверяет архитектуру Arch-ветки. [Определение ОС](../../install/install.sh#L5) · [Актуальные проверки](TEST_RESULTS.md)

[commit]: https://github.com/ilyamiro/serpantinum/commit/57ab121b80358b4bd51bc0d49ecef40a6003d6db
[deps]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules/deps.sh#L3
[pacman]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules/pm/pacman.sh
[dnf]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules/pm/dnf.sh
[void]: https://github.com/ilyamiro/serpantinum/blob/57ab121b80358b4bd51bc0d49ecef40a6003d6db/install/modules/pm/void.sh
[nix]: https://github.com/ilyamiro/serpantinum/tree/57ab121b80358b4bd51bc0d49ecef40a6003d6db/nix
[terra]: https://developer.fyralabs.com/andaman/installation
