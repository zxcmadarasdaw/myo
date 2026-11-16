# Serpantinum AI — продолжение

Этап 7 завершил разработку и проверки на доступных стендах. Нового этапа в ТЗ нет. Открыта ручная приёмка в живой сессии Fedora 45. Продолжать её только после сообщения пользователя «Продолжай» и при доступной целевой среде.

1. Проверить `git status --short` и прочитать [ROADMAP.md](ROADMAP.md), [PROGRESS.md](PROGRESS.md), [ARCHITECTURE.md](ARCHITECTURE.md) и [TESTS.md](TESTS.md). Сохранить правки пользователя.
2. Выполнить сценарий Fedora из [FINAL_REPORT.md](FINAL_REPORT.md) и сверить автоматические результаты в [TESTS.md](TESTS.md).
3. Измерить CPU и RSS Quickshell до открытия AI, во время генерации и после закрытия чата. Замер Ollama записать отдельно.
4. Зафиксировать версии Fedora, Hyprland, Quickshell, Ollama и модель, результаты действий и регрессий, ограничения и найденные ошибки. Обновить [FINAL_REPORT.md](FINAL_REPORT.md).

Формат отчёта — `SERPANTINUM AI — STAGE REPORT` с полями `Stage`, `Status`, `Implemented`, `Changed Files`, `Tests`, `Known Issues`, `Next Stage` и `Resume Instructions`. Последняя строка — «Этап завершён. Ожидаю команду ПРОДОЛЖАЙ».
