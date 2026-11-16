# Компоненты Fedora 45 x86_64

Все четыре файла из `voninsll` совпали по размеру и SHA-256 с закреплёнными метаданными. Бинарники на Windows не запускались.

| Файл | Байты | SHA-256 | Формат и роль |
|---|---:|---|---|
| sing-box-1.14.4-linux-amd64 (1).tar.gz | 31710753 | 699a1b510aa4396b2176d32d1181920399ebf1e267835da6f3b598d0f7c24968 | TAR.GZ, официальный SagerNet 1.14.4. Движок Proxy и TUN, ELF64 x86-64, извлекается установщиком. |
| iproute-7.0.0-2.fc45.x86_64.rpm | 935873 | 20e712af1dc17b629709345af74e4da72579ae4f8e34f334b32fd881cf5614c0 | Fedora 45 x86_64. Интерфейс и маршруты TUN. Устанавливается целиком. |
| nftables-1.1.6-4.fc45.x86_64.rpm | 459829 | 6cd8d5b71430fa8aec48d012aa3b663d53dbf703ac7d753be633d35716b7dc64 | Fedora 45 x86_64. Диагностика и очистка правил TUN. Устанавливается целиком. |
| python3-pyyaml-6.0.3-6.fc45.x86_64.rpm | 244653 | 2e73b059d547089b7352922f75fc55a3ea4037ae5aadd124d7e4b451a8fc3527 | Fedora 45 x86_64. Импорт Clash YAML в обоих режимах. Устанавливается целиком. |

Архив дополнительно содержит LICENSE и libcronet.so (ELF64 x86-64). Архив хранится целиком с оригинальным именем. Текущие Proxy и TUN конфигурации не используют Cronet. Для RPM проверены заголовки формата и совпадение с Fedora lock-файлом. Проверка подписи выполняется DNF на Fedora. Остальные 18 RPM из существующего кэша входят в комплект зависимостей.

- [Релиз SagerNet](https://github.com/SagerNet/sing-box/releases/tag/v1.14.4)
- [Метаданные архива GitHub](https://api.github.com/repos/SagerNet/sing-box/releases/tags/v1.14.4)
- [Каталог Fedora 45](https://dl.fedoraproject.org/pub/fedora/linux/releases/45/Everything/x86_64/os/Packages/)
- [Список RPM, размеры и SHA-256](../../packaging/vpn-bundle/fedora45-rpms.lock.json)
