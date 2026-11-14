#!/usr/bin/env python3
"""VPN subscription client for Serpantinum (stage 1: local proxy, no root).

    python3 serp_vpn.py COMMAND [--json]

Commands:
  test [LINK | -]     download/parse LINK (or stdin), print the servers and run
                      `sing-box check` on a generated config. Saves and starts
                      nothing. Prefer `-` and stdin: arguments are visible in ps.
  set-source          read a subscription link / server links from stdin, save it
                      (mode 600) and update
  update [--auto]     download + parse + check; the config is replaced only if
                      `sing-box check` succeeds (--auto: only when older than the
                      configured interval; silent without a subscription)
  list                servers (no credentials)
  status              state, current server, proxy address
  connect | disconnect
  select TAG          switch server (live through the Clash API when connected)
  ping                delay test of all servers, done by sing-box through its Clash
                      API (a short-lived sing-box without inbounds when not connected).
                      The shell runs this only while the network panel is open.
  clear               forget all subscriptions (stops the proxy)
  ipcheck             external IP and its country, fetched through the running VPN
                      (proxy or TUN); refuses when nothing is connected

Subscriptions (several can be saved; one is active, its servers are the ones listed):
  subs                list: id, name, kind/host (never the link), last update result
  sub-add [--name=N]  read a link from stdin, save it as a new subscription, make it
                      active and update; nothing is kept when the update fails
  sub-use ID          make ID active and update (the previous one stays on failure)
  sub-rename ID NAME
  sub-remove ID       forget one subscription (the next one becomes active)

sing-box (no root; see serp_vpn_singbox.py):
  singbox-info        which sing-box is used, its version, other ones found
  singbox-install     download the official release for this machine into
                      ~/.local/share/serpantinum/vpn/bin, with progress lines on stdout;
                      SIGTERM cancels; used only after `sing-box version` works
  singbox-use PATH    use this sing-box file (checked by running `version`); "" = automatic

Stage 2, TUN (whole system through the VPN; needs the installer's serpantinum-vpn service):
  mode proxy|tun      choose the mode (reconnects when connected)
  check               DNS (systemd-resolved) and other-VPN conflict warnings
  force-off           emergency off: kill the service, remove its routes, stop the proxy

  In TUN mode `connect` sends the server list (not the link) to the root helper through
  pkexec; the helper rebuilds the config from its own template, checks it with
  `sing-box check` and writes /etc/serpantinum-vpn/config.json (600). The service is then
  started with systemctl; the polkit rule lets only the installing user do both.

Files
  ~/.config/serpantinum/vpn/source         the active link or pasted text     (600)
  ~/.config/serpantinum/vpn/subs/ID        each saved subscription's link     (600)
  ~/.config/serpantinum/vpn/subscriptions.json  names, active id, update results (600)
  ~/.config/serpantinum/vpn/settings.json  ports, interval, selection, secret (600)
  ~/.local/state/serpantinum/vpn/          servers.json, config.json, last_update.json,
                                           pings.json, sing-box.log, sing-box.pid
                                           (files 600, directory 700)

The subscription link is never printed, logged or put on a command line by this
script. sing-box listens on 127.0.0.1 only (mixed HTTP/SOCKS5 proxy + Clash API
protected by a random secret).
"""
import base64
import importlib.util
import ipaddress
import json
import os
import re
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

# ---- locations -------------------------------------------------------------------------


def _xdg(var, fallback):
    v = os.environ.get(var, "")
    return v if v else os.path.join(os.path.expanduser("~"), fallback)


def config_dir():
    return os.environ.get("SERP_VPN_CONFIG_DIR") or os.path.join(_xdg("XDG_CONFIG_HOME", ".config"), "serpantinum", "vpn")


def state_dir():
    if os.environ.get("SERP_VPN_STATE_DIR"):
        return os.environ["SERP_VPN_STATE_DIR"]
    base = os.environ.get("QS_STATE_DIR") or os.path.join(_xdg("XDG_STATE_HOME", ".local/state"), "serpantinum")
    return os.path.join(base, "vpn")


def managed_singbox():
    """Where `singbox-install` puts sing-box (same rule as serp_vpn_singbox.managed_path)."""
    base = os.environ.get("SERP_VPN_BIN_DIR") or os.path.join(_xdg("XDG_DATA_HOME", ".local/share"),
                                                              "serpantinum", "vpn", "bin")
    return os.path.join(base, "sing-box")


def _executable(path):
    return bool(path) and os.path.isfile(path) and os.access(path, os.X_OK)


def singbox_location():
    """(path, source): source is env | chosen | system | managed | "" (none)."""
    override = os.environ.get("SERP_VPN_SINGBOX")
    if override is not None:                  # tests / custom location; "" means "not installed"
        return (override, "env") if override and os.path.isfile(override) else ("", "")
    chosen = _merge_settings(read_json(os.path.join(config_dir(), "settings.json"), {})).get("singboxPath", "")
    if _executable(chosen):                   # picked in the panel, or installed by singbox-install
        return chosen, ("managed" if chosen == managed_singbox() else "chosen")
    found = shutil.which("sing-box")
    if found:
        return found, "system"
    if _executable(managed_singbox()):
        return managed_singbox(), "managed"
    return "", ""


def singbox_bin():
    return singbox_location()[0]


def _singbox_module():
    """serp_vpn_singbox lives next to this file (also when this file is loaded by path in tests)."""
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:
        sys.path.insert(0, here)
    import serp_vpn_singbox
    return serp_vpn_singbox


INSTALL_HINT = "sudo dnf config-manager addrepo --from-repofile=https://sing-box.app/sing-box.repo && sudo dnf install sing-box"

DEFAULT_SETTINGS = {
    "updateHours": 12,
    "proxyPort": 2080,
    "apiPort": 9097,
    "probePort": 9098,
    "userAgent": "v2rayN/7.0",
    "testUrl": "https://www.gstatic.com/generate_204",
    "selected": "",
    "secret": "",
    "mode": "proxy",          # "proxy": local proxy as the user; "tun": system service (stage 2)
    "singboxPath": "",        # chosen or installed sing-box ("" = automatic: PATH, then the installed one)
}


def _ensure_dir(path):
    os.makedirs(path, mode=0o700, exist_ok=True)
    try:
        os.chmod(path, 0o700)
    except OSError:
        pass


def write_private(path, text):
    """Atomic write; mkstemp creates the file with mode 600, so it is never readable by others."""
    _ensure_dir(os.path.dirname(path))
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def read_text(path, default=""):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except (OSError, UnicodeDecodeError):
        return default


def read_json(path, default):
    try:
        return json.loads(read_text(path, ""))
    except ValueError:
        return default


def _merge_settings(data):
    s = dict(DEFAULT_SETTINGS)
    if isinstance(data, dict):
        for k, v in data.items():
            if k in DEFAULT_SETTINGS and isinstance(v, type(DEFAULT_SETTINGS[k])) and not isinstance(v, bool):
                s[k] = v
    for k in ("proxyPort", "apiPort", "probePort"):
        if not 1024 <= int(s[k]) <= 65535:
            s[k] = DEFAULT_SETTINGS[k]
    s["updateHours"] = max(1, min(168, int(s["updateHours"])))
    if s["mode"] not in ("proxy", "tun"):
        s["mode"] = "proxy"
    return s


def load_settings():
    s = _merge_settings(read_json(os.path.join(config_dir(), "settings.json"), {}))
    if not s["secret"]:
        s["secret"] = secrets.token_hex(16)
        save_settings(s)
    return s


def load_settings_readonly():
    s = _merge_settings(read_json(os.path.join(config_dir(), "settings.json"), {}))
    if not s["secret"]:
        s["secret"] = secrets.token_hex(16)
    return s


def save_settings(s):
    write_private(os.path.join(config_dir(), "settings.json"), json.dumps(s, indent=2, ensure_ascii=False))


# ---- messages --------------------------------------------------------------------------

MESSAGES = {
    "empty": ("The subscription is empty: the server returned nothing.",
              "Подписка пустая: сервер ничего не вернул."),
    "html": ("The link returned a web page, not a subscription. Check the link (copy it from the provider again).",
             "По ссылке открылась веб-страница, а не подписка. Проверьте ссылку (скопируйте её у провайдера заново)."),
    "unknown_format": ("Not a subscription: expected server links (vless://, vmess://, trojan://, ss://, hysteria2://, tuic://), base64, Clash YAML or sing-box JSON.",
                       "Это не подписка: ожидаются ссылки серверов (vless://, vmess://, trojan://, ss://, hysteria2://, tuic://), base64, Clash YAML или JSON sing-box."),
    "no_servers": ("The subscription was read, but it contains no supported servers. {detail}",
                   "Подписка прочитана, но в ней нет поддерживаемых серверов. {detail}"),
    "bad_json": ("The JSON in the subscription is damaged: {detail}",
                 "JSON в подписке повреждён: {detail}"),
    "bad_yaml": ("The Clash YAML in the subscription is damaged: {detail}",
                 "Clash YAML в подписке повреждён: {detail}"),
    "need_yaml": ("This is a Clash subscription; reading it needs PyYAML: sudo dnf install python3-pyyaml",
                  "Это подписка Clash; для чтения нужен PyYAML: sudo dnf install python3-pyyaml"),
    "happ_encrypted": ("happ:// links are encrypted by the Happ app. Paste the original https:// subscription link instead.",
                       "Ссылки happ:// зашифрованы приложением Happ. Вставьте исходную https://-ссылку подписки."),
    "no_source": ("No subscription yet. Paste a link.", "Нет подписки. Вставьте ссылку."),
    "fetch_http": ("The subscription server answered HTTP {detail}.", "Сервер подписки ответил HTTP {detail}."),
    "fetch_failed": ("Could not download the subscription: {detail}", "Не удалось скачать подписку: {detail}"),
    "too_large": ("The subscription is larger than 5 MB.", "Подписка больше 5 МБ."),
    "no_singbox": ("sing-box is not installed. Download it in the VPN panel, or install it: " + INSTALL_HINT,
                   "sing-box не установлен. Скачайте его в панели VPN или установите: " + INSTALL_HINT),
    "check_failed": ("sing-box rejected the generated config: {detail}",
                     "sing-box отклонил созданный конфиг: {detail}"),
    "no_config": ("There is no checked config yet. Update the subscription first.",
                  "Ещё нет проверенного конфига. Сначала обновите подписку."),
    "start_failed": ("sing-box did not start: {detail}", "sing-box не запустился: {detail}"),
    "port_busy": ("Port {detail} on 127.0.0.1 is already used by another program.",
                  "Порт {detail} на 127.0.0.1 уже занят другой программой."),
    "unknown_server": ("No such server: {detail}", "Нет такого сервера: {detail}"),
    "api_failed": ("sing-box does not answer on its control port: {detail}",
                   "sing-box не отвечает на управляющем порту: {detail}"),
    "kept_old": ("The previous working config is kept.", "Оставлен прежний рабочий конфиг."),
    # stage 2: TUN
    "tun_not_installed": ("TUN mode is not installed: run the Serpantinum installer again (it adds the serpantinum-vpn service).",
                          "Режим TUN не установлен: запустите установщик Serpantinum ещё раз (он добавит службу serpantinum-vpn)."),
    "not_authorized": ("The system did not allow controlling the VPN service (polkit). Run the installer again so it adds the rule for your user. {detail}",
                       "Система не разрешила управлять службой VPN (polkit). Запустите установщик ещё раз, чтобы он добавил правило для вашего пользователя. {detail}"),
    "tun_apply_failed": ("Could not apply the system VPN configuration: {detail}",
                         "Не удалось применить системную конфигурацию VPN: {detail}"),
    "no_singbox_root": ("TUN mode needs sing-box in /usr/bin or /usr/local/bin. Install it: " + INSTALL_HINT,
                        "Для режима TUN нужен sing-box в /usr/bin или /usr/local/bin. Установите: " + INSTALL_HINT),
    "old_singbox": ("TUN mode needs sing-box {detail} or newer. Update sing-box: sudo dnf upgrade sing-box",
                    "Для режима TUN нужен sing-box {detail} или новее. Обновите: sudo dnf upgrade sing-box"),
    "service_failed": ("The serpantinum-vpn service did not start: {detail}",
                       "Служба serpantinum-vpn не запустилась: {detail}"),
    "stop_timeout": ("The serpantinum-vpn service does not stop. Use Force off (serpantinum vpn force-off).",
                     "Служба serpantinum-vpn не останавливается. Нажмите «Выключить принудительно» (serpantinum vpn force-off)."),
    "cleanup_failed": ("The service is stopped, but leftover routes could not be removed: {detail}",
                       "Служба остановлена, но не удалось убрать оставшиеся маршруты: {detail}"),
    "bad_mode": ("Unknown mode: {detail} (use proxy or tun).", "Неизвестный режим: {detail} (proxy или tun)."),
    "dns_no_resolved": ("systemd-resolved is not running. TUN still intercepts DNS on port 53, but programs with their own encrypted DNS bypass the VPN's DNS.",
                        "systemd-resolved не запущен. TUN всё равно перехватывает DNS на порту 53, но программы со своим шифрованным DNS обходят DNS VPN."),
    "dns_not_stub": ("DNS is not handled by systemd-resolved (/etc/resolv.conf -> {detail}). Port 53 is still intercepted; make sure your resolver does not use its own encrypted DNS.",
                     "DNS обслуживает не systemd-resolved (/etc/resolv.conf -> {detail}). Порт 53 всё равно перехватывается; проверьте, что ваш резолвер не использует свой шифрованный DNS."),
    "dns_dot": ("systemd-resolved uses DNS-over-TLS: these queries go through the VPN tunnel, but to your usual DNS server, not the VPN's.",
                "systemd-resolved использует DNS-over-TLS: такие запросы идут через туннель, но к вашему обычному DNS-серверу, а не к DNS VPN."),
    "conflict_tailscale": ("Tailscale is running. With TUN on, Tailscale and MagicDNS may stop working; turn one of them off.",
                           "Запущен Tailscale. При включённом TUN Tailscale и MagicDNS могут перестать работать; выключите что-то одно."),
    "conflict_iface": ("Another VPN interface is up: {detail}. Two VPNs at once usually conflict.",
                       "Поднят интерфейс другого VPN: {detail}. Два VPN одновременно обычно конфликтуют."),
    "conflict_proc": ("Another VPN program is running: {detail}.", "Запущена другая VPN-программа: {detail}."),
    "conflict_nm": ("A NetworkManager VPN connection is active: {detail}.", "Активно VPN-подключение NetworkManager: {detail}."),
    # subscriptions
    "sub_unknown": ("No such subscription: {detail}", "Нет такой подписки: {detail}"),
    "sub_bad_name": ("A subscription name must be 1-60 printable characters.",
                     "Название подписки: от 1 до 60 печатных символов."),
    # exit IP check
    "not_connected": ("The VPN is not connected.", "VPN не подключён."),
    "ip_failed": ("Could not check the external IP through the VPN: {detail}",
                  "Не удалось проверить внешний IP через VPN: {detail}"),
    # sing-box download / choice (serp_vpn_singbox.py)
    "sb_offline": ("No internet connection: github.com could not be resolved. The VPN panel keeps working; try again later or choose an installed sing-box.",
                   "Нет подключения к интернету: адрес github.com не определяется. Панель VPN продолжает работать; повторите позже или выберите установленный sing-box."),
    "sb_timeout": ("GitHub stopped answering (no data for 30 s, four attempts). Press Retry, or install sing-box with dnf.",
                   "GitHub перестал отвечать (30 с без данных, четыре попытки). Нажмите «Повторить» или установите sing-box через dnf."),
    "sb_tls": ("The secure connection to GitHub failed ({detail}). Check the system date and time.",
               "Не удалось установить защищённое соединение с GitHub ({detail}). Проверьте системные дату и время."),
    "sb_unreachable": ("GitHub could not be reached: {detail}", "Не удалось связаться с GitHub: {detail}"),
    "sb_http": ("GitHub answered HTTP {detail}.", "GitHub ответил HTTP {detail}."),
    "sb_no_release": ("The latest sing-box release could not be read ({detail}).",
                      "Не удалось прочитать последний выпуск sing-box ({detail})."),
    "sb_no_asset": ("The release has no file for this computer: {detail}",
                    "В выпуске нет файла для этого компьютера: {detail}"),
    "sb_arch": ("sing-box is not published for this processor: {detail}",
                "sing-box не выпускается для этого процессора: {detail}"),
    "sb_too_large": ("The download is unexpectedly large ({detail}); stopped.",
                     "Загрузка неожиданно большая ({detail}); остановлена."),
    "sb_incomplete": ("The download ended early ({detail}).", "Загрузка оборвалась ({detail})."),
    "sb_checksum": ("The download is damaged: its SHA-256 does not match the one GitHub published ({detail}). Nothing was installed.",
                    "Загрузка повреждена: SHA-256 не совпадает с опубликованным на GitHub ({detail}). Ничего не установлено."),
    "sb_bad_archive": ("The downloaded archive is not a sing-box release ({detail}). Nothing was installed.",
                       "Скачанный архив не похож на выпуск sing-box ({detail}). Ничего не установлено."),
    "sb_not_working": ("The downloaded sing-box does not run on this system ({detail}). Nothing was installed.",
                       "Скачанный sing-box не запускается в этой системе ({detail}). Ничего не установлено."),
    "sb_bad_path": ("This file is not a working sing-box ({detail}).", "Этот файл не является рабочим sing-box ({detail})."),
    "sb_no_digest": ("GitHub did not publish a SHA-256 digest for {detail}.",
                     "На GitHub нет контрольной суммы SHA-256 для {detail}."),
    "setup_file": ("Could not read this VPN configuration file: {detail}.",
                   "Не удалось прочитать файл конфигурации VPN: {detail}."),
    "setup_packages": ("Fedora could not install the VPN components: {detail}",
                       "Fedora не смогла установить компоненты VPN: {detail}"),
    "setup_admin": ("System packages require the Serpantinum package helper, DNF5 and a polkit session.",
                    "Для системных пакетов нужны помощник установки Serpantinum, DNF5 и сеанс polkit."),
    "setup_auth": ("System package authorization was denied or no graphical polkit agent is running.",
                   "Авторизация установки отклонена или графический агент polkit не запущен."),
    "setup_tun": ("The TUN device (/dev/net/tun) is unavailable.", "Устройство TUN (/dev/net/tun) недоступно."),
    "setup_storage": ("Could not write the VPN files: {detail}.", "Не удалось записать файлы VPN: {detail}."),
    "setup_connected": ("Disconnect the current VPN before preparing a replacement.",
                        "Перед настройкой другого VPN отключите текущее подключение."),
}


def lang_ru():
    lang = (os.environ.get("SERP_VPN_LANG") or os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES")
            or os.environ.get("LANG") or "")
    return lang.lower().startswith(("ru", "uk", "be"))


def msg(code, detail=""):
    en, ru = MESSAGES.get(code, (code, code))
    return (ru if lang_ru() else en).replace("{detail}", str(detail)).strip()


class VpnError(Exception):
    def __init__(self, code, detail=""):
        super().__init__(code)
        self.code = code
        self.detail = detail

    def as_dict(self):
        return {"code": self.code, "detail": str(self.detail), "message": msg(self.code, self.detail)}


# ---- countries (offline) ---------------------------------------------------------------
# ISO code: (English, Russian, extra keywords). A flag emoji wins over a code token,
# a code token over a country/city name.

COUNTRIES = {
    "AE": ("United Arab Emirates", "ОАЭ", ["uae", "emirates", "dubai", "дубай", "эмираты"]),
    "AM": ("Armenia", "Армения", ["yerevan", "ереван"]),
    "AR": ("Argentina", "Аргентина", ["buenos aires"]),
    "AT": ("Austria", "Австрия", ["vienna", "вена"]),
    "AU": ("Australia", "Австралия", ["sydney", "melbourne", "сидней"]),
    "AZ": ("Azerbaijan", "Азербайджан", ["baku", "баку"]),
    "BE": ("Belgium", "Бельгия", ["brussels", "брюссель"]),
    "BG": ("Bulgaria", "Болгария", ["sofia", "софия"]),
    "BR": ("Brazil", "Бразилия", ["sao paulo", "сан-паулу"]),
    "BY": ("Belarus", "Беларусь", ["minsk", "минск", "белоруссия"]),
    "CA": ("Canada", "Канада", ["toronto", "montreal", "vancouver", "торонто"]),
    "CH": ("Switzerland", "Швейцария", ["zurich", "geneva", "цюрих"]),
    "CL": ("Chile", "Чили", ["santiago"]),
    "CN": ("China", "Китай", ["beijing", "shanghai", "пекин"]),
    "CY": ("Cyprus", "Кипр", ["nicosia", "limassol"]),
    "CZ": ("Czechia", "Чехия", ["czech republic", "prague", "прага"]),
    "DE": ("Germany", "Германия", ["deutschland", "frankfurt", "berlin", "munich", "nuremberg",
                                   "франкфурт", "берлин", "мюнхен", "нюрнберг"]),
    "DK": ("Denmark", "Дания", ["copenhagen", "копенгаген"]),
    "EE": ("Estonia", "Эстония", ["tallinn", "таллин"]),
    "ES": ("Spain", "Испания", ["madrid", "barcelona", "мадрид"]),
    "FI": ("Finland", "Финляндия", ["helsinki", "хельсинки"]),
    "FR": ("France", "Франция", ["paris", "marseille", "париж"]),
    "GB": ("United Kingdom", "Великобритания", ["britain", "england", "london", "лондон", "англия", "британия"]),
    "GE": ("Georgia", "Грузия", ["tbilisi", "тбилиси"]),
    "GR": ("Greece", "Греция", ["athens", "афины"]),
    "HK": ("Hong Kong", "Гонконг", ["hongkong"]),
    "HU": ("Hungary", "Венгрия", ["budapest", "будапешт"]),
    "ID": ("Indonesia", "Индонезия", ["jakarta"]),
    "IE": ("Ireland", "Ирландия", ["dublin", "дублин"]),
    "IL": ("Israel", "Израиль", ["tel aviv", "тель-авив"]),
    "IN": ("India", "Индия", ["mumbai", "delhi", "bangalore", "мумбаи"]),
    "IR": ("Iran", "Иран", ["tehran"]),
    "IS": ("Iceland", "Исландия", ["reykjavik"]),
    "IT": ("Italy", "Италия", ["milan", "rome", "милан", "рим"]),
    "JP": ("Japan", "Япония", ["tokyo", "osaka", "токио"]),
    "KG": ("Kyrgyzstan", "Киргизия", ["bishkek", "бишкек", "кыргызстан"]),
    "KR": ("South Korea", "Южная Корея", ["korea", "seoul", "корея", "сеул"]),
    "KZ": ("Kazakhstan", "Казахстан", ["almaty", "astana", "алматы", "астана"]),
    "LT": ("Lithuania", "Литва", ["vilnius", "вильнюс"]),
    "LU": ("Luxembourg", "Люксембург", []),
    "LV": ("Latvia", "Латвия", ["riga", "рига"]),
    "MD": ("Moldova", "Молдова", ["chisinau", "кишинев", "кишинёв", "молдавия"]),
    "MX": ("Mexico", "Мексика", []),
    "MY": ("Malaysia", "Малайзия", ["kuala lumpur"]),
    "NL": ("Netherlands", "Нидерланды", ["holland", "amsterdam", "голландия", "амстердам"]),
    "NO": ("Norway", "Норвегия", ["oslo", "осло"]),
    "NZ": ("New Zealand", "Новая Зеландия", []),
    "PL": ("Poland", "Польша", ["warsaw", "варшава"]),
    "PT": ("Portugal", "Португалия", ["lisbon", "лиссабон"]),
    "RO": ("Romania", "Румыния", ["bucharest", "бухарест"]),
    "RS": ("Serbia", "Сербия", ["belgrade", "белград"]),
    "RU": ("Russia", "Россия", ["moscow", "saint petersburg", "москва", "петербург"]),
    "SE": ("Sweden", "Швеция", ["stockholm", "стокгольм"]),
    "SG": ("Singapore", "Сингапур", []),
    "SI": ("Slovenia", "Словения", ["ljubljana"]),
    "SK": ("Slovakia", "Словакия", ["bratislava"]),
    "TH": ("Thailand", "Таиланд", ["bangkok", "бангкок"]),
    "TR": ("Turkey", "Турция", ["türkiye", "turkiye", "istanbul", "стамбул"]),
    "TW": ("Taiwan", "Тайвань", ["taipei"]),
    "UA": ("Ukraine", "Украина", ["kyiv", "kiev", "киев"]),
    "US": ("United States", "США", ["usa", "america", "new york", "los angeles", "chicago", "dallas", "miami",
                                    "seattle", "silicon valley", "америка", "нью-йорк"]),
    "UZ": ("Uzbekistan", "Узбекистан", ["tashkent", "ташкент"]),
    "VN": ("Vietnam", "Вьетнам", ["hanoi"]),
    "ZA": ("South Africa", "ЮАР", ["johannesburg"]),
}
CODE_ALIASES = {"UK": "GB", "USA": "US", "GER": "DE", "DEU": "DE", "NLD": "NL", "RUS": "RU", "FRA": "FR",
                "JPN": "JP", "SGP": "SG", "KOR": "KR", "TUR": "TR", "FIN": "FI", "POL": "PL", "SWE": "SE",
                "UAE": "AE", "KAZ": "KZ", "CAN": "CA", "AUS": "AU", "CHE": "CH", "AUT": "AT", "EST": "EE",
                "LVA": "LV", "LTU": "LT", "HKG": "HK", "ESP": "ES", "ITA": "IT", "GBR": "GB"}
# Two-letter tokens that are ordinary words/abbreviations in server names, not countries.
CODE_STOPWORDS = {"IN", "IS", "NO", "AT", "BE", "ID", "IT", "TO", "ME", "MY", "DE", "AM"}


def _keyword_table():
    table = []
    for code, (en, ru, extra) in COUNTRIES.items():
        for w in [en, ru] + extra:
            table.append((w.lower(), code))
    table.sort(key=lambda t: -len(t[0]))      # longest first: "south korea" before "korea"
    return table


KEYWORDS = _keyword_table()


def detect_country(name):
    """ISO code from a flag emoji, a country code token or a country/city name. Offline."""
    if not name:
        return ""
    chars = list(name)
    for i in range(len(chars) - 1):
        a, b = ord(chars[i]), ord(chars[i + 1])
        if 0x1F1E6 <= a <= 0x1F1FF and 0x1F1E6 <= b <= 0x1F1FF:
            return chr(a - 0x1F1E6 + 65) + chr(b - 0x1F1E6 + 65)
    tokens = re.findall(r"(?<![A-Za-z])([A-Z]{2,3})(?![A-Za-z])", name)
    for token in tokens:
        code = CODE_ALIASES.get(token, token)
        if code in COUNTRIES and token not in CODE_STOPWORDS:
            return code
    low = name.lower()
    for word, code in KEYWORDS:
        if len(word) <= 3:
            if re.search(r"(?<![a-zа-яё])" + re.escape(word) + r"(?![a-zа-яё])", low):
                return code
        elif word in low:
            return code
    # "IT-1", "NO 2", "DE": an ambiguous code counts only when it starts the name
    m = re.match(r"^\W*([A-Z]{2})(?![A-Za-z])", name)
    if m and m.group(1) in COUNTRIES:
        return m.group(1)
    return ""


def country_name(code):
    if code not in COUNTRIES:
        return ""
    en, ru, _ = COUNTRIES[code]
    return ru if lang_ru() else en


def flag(code):
    if len(code) != 2 or not code.isalpha():
        return ""
    return "".join(chr(0x1F1E6 + ord(c) - 65) for c in code.upper())


# ---- single links ----------------------------------------------------------------------


class Unsupported(Exception):
    pass


def _b64decode(s):
    s = re.sub(r"\s+", "", s).replace("-", "+").replace("_", "/")
    s += "=" * (-len(s) % 4)
    return base64.b64decode(s, validate=True)


def _q(params, *names, default=""):
    for n in names:
        v = params.get(n)
        if v:
            return v[0] if isinstance(v, list) else v
    return default


def _truthy(v):
    return str(v).strip().lower() in ("1", "true", "yes", "on")


def _is_ip(host):
    return bool(re.fullmatch(r"[0-9.]+", host)) or ":" in host


def _port(value):
    try:
        p = int(str(value).strip())
    except (TypeError, ValueError):
        raise ValueError("invalid port")
    if not 1 <= p <= 65535:
        raise ValueError("invalid port")
    return p


def _split_host_port(netloc):
    """user@host:port -> (user, host, port_text); IPv6 in brackets."""
    user = ""
    if "@" in netloc:
        user, netloc = netloc.rsplit("@", 1)
    if netloc.startswith("["):
        end = netloc.find("]")
        if end < 0:
            raise ValueError("invalid IPv6 address")
        host, rest = netloc[1:end], netloc[end + 1:]
        port = rest[1:] if rest.startswith(":") else ""
    elif ":" in netloc:
        host, port = netloc.rsplit(":", 1)
    else:
        host, port = netloc, ""
    return urllib.parse.unquote(user), host, port


def _tls(params, host, default_on=False):
    security = str(_q(params, "security", default="tls" if default_on else "none")).lower()
    if security in ("", "none"):
        return None
    if security == "xtls":
        raise Unsupported("XTLS (legacy) is not supported by sing-box")
    tls = {"enabled": True}
    sni = _q(params, "sni", "peer", "serverName")
    server_name = sni or (host if not _is_ip(host) else "")
    if server_name:
        tls["server_name"] = server_name
    if _truthy(_q(params, "allowInsecure", "insecure", "allow_insecure")):
        tls["insecure"] = True
    alpn = _q(params, "alpn")
    if alpn:
        tls["alpn"] = [a for a in urllib.parse.unquote(alpn).split(",") if a]
    fp = _q(params, "fp", "fingerprint")
    if security == "reality":
        pbk = _q(params, "pbk", "publicKey")
        if not pbk:
            raise ValueError("REALITY without public key (pbk)")
        tls["reality"] = {"enabled": True, "public_key": pbk, "short_id": _q(params, "sid", "shortId")}
        tls["utls"] = {"enabled": True, "fingerprint": fp or "chrome"}
    elif fp:
        tls["utls"] = {"enabled": True, "fingerprint": fp}
    return tls


def _transport(net, params, host_header="", path="", service=""):
    net = (net or "tcp").lower()
    if net in ("tcp", "raw", "none", ""):
        if str(_q(params, "headerType")).lower() == "http":
            raise Unsupported("TCP with HTTP header obfuscation is not supported by sing-box")
        return None
    if net == "ws":
        t = {"type": "ws", "path": path or "/"}
        m = re.search(r"[?&]ed=(\d+)", t["path"])
        if m:
            t["path"] = re.sub(r"[?&]ed=\d+", "", t["path"]) or "/"
            t["max_early_data"] = int(m.group(1))
            t["early_data_header_name"] = "Sec-WebSocket-Protocol"
        if host_header:
            t["headers"] = {"Host": host_header}
        return t
    if net == "grpc":
        return {"type": "grpc", "service_name": service or path or ""}
    if net in ("http", "h2"):
        t = {"type": "http"}
        if host_header:
            t["host"] = [h for h in host_header.split(",") if h]
        if path:
            t["path"] = path
        return t
    if net == "httpupgrade":
        t = {"type": "httpupgrade", "path": path or "/"}
        if host_header:
            t["host"] = host_header
        return t
    if net == "quic":
        return {"type": "quic"}
    raise Unsupported(f"transport {net!r} is not supported by sing-box")


def _std_link_parts(link):
    sp = urllib.parse.urlsplit(link)
    user, host, port = _split_host_port(sp.netloc)
    params = urllib.parse.parse_qs(sp.query)
    name = urllib.parse.unquote(sp.fragment).strip()
    return user, host, port, params, name


def _link_transport(p):
    return _transport(_q(p, "type", default="tcp"), p, urllib.parse.unquote(_q(p, "host")),
                      urllib.parse.unquote(_q(p, "path")), urllib.parse.unquote(_q(p, "serviceName")))


def parse_vless(link):
    uuid, host, port, p, name = _std_link_parts(link)
    if not uuid or not host:
        raise ValueError("missing user id or address")
    params = {"uuid": uuid}
    flow = _q(p, "flow")
    if flow:
        params["flow"] = flow
    tls = _tls(p, host)
    if tls:
        params["tls"] = tls
    tr = _link_transport(p)
    if tr:
        params["transport"] = tr
    params["packet_encoding"] = _q(p, "packetEncoding", default="xudp")
    return "vless", host, _port(port), params, name


def parse_vmess(link):
    body = link[len("vmess://"):].split("#", 1)[0]
    try:
        data = json.loads(_b64decode(body).decode("utf-8"))
    except Exception:
        if "@" in body:              # vless-like form vmess://uuid@host:port?...
            uuid, host, port, p, name = _std_link_parts(link)
            params = {"uuid": uuid, "security": _q(p, "encryption", default="auto"), "alter_id": 0}
            tls = _tls(p, host)
            if tls:
                params["tls"] = tls
            tr = _link_transport(p)
            if tr:
                params["transport"] = tr
            return "vmess", host, _port(port), params, name
        raise ValueError("vmess link is not valid base64 JSON")
    if not isinstance(data, dict):
        raise ValueError("vmess link is not a JSON object")
    host = str(data.get("add", "")).strip()
    uuid = str(data.get("id", "")).strip()
    if not host or not uuid:
        raise ValueError("missing address or id")
    try:
        aid = int(str(data.get("aid") or 0))
    except ValueError:
        aid = 0
    params = {"uuid": uuid, "security": str(data.get("scy") or "auto"), "alter_id": aid}
    tls_kind = str(data.get("tls", "")).lower()
    q = {"security": tls_kind if tls_kind in ("tls", "reality") else "none",
         "sni": str(data.get("sni", "")), "alpn": str(data.get("alpn", "")), "fp": str(data.get("fp", "")),
         "allowInsecure": str(data.get("allowInsecure", "")), "pbk": str(data.get("pbk", "")),
         "sid": str(data.get("sid", ""))}
    if str(data.get("net", "tcp")) == "tcp" and str(data.get("type", "")) == "http":
        raise Unsupported("TCP with HTTP header obfuscation is not supported by sing-box")
    tls = _tls({k: v for k, v in q.items() if v}, host)
    if tls:
        params["tls"] = tls
    path = str(data.get("path", ""))
    tr = _transport(str(data.get("net", "tcp")), {}, str(data.get("host", "")), path, path)
    if tr:
        params["transport"] = tr
    return "vmess", host, _port(data.get("port")), params, str(data.get("ps", "")).strip()


def parse_trojan(link):
    password, host, port, p, name = _std_link_parts(link)
    if not password or not host:
        raise ValueError("missing password or address")
    params = {"password": password}
    tls = _tls(p, host, default_on=True)
    if tls:
        params["tls"] = tls
    tr = _link_transport(p)
    if tr:
        params["transport"] = tr
    return "trojan", host, _port(port or 443), params, name


SS_METHODS = {"aes-128-gcm", "aes-192-gcm", "aes-256-gcm", "chacha20-ietf-poly1305", "xchacha20-ietf-poly1305",
              "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm", "2022-blake3-chacha20-poly1305", "none",
              "aes-128-ctr", "aes-192-ctr", "aes-256-ctr", "aes-128-cfb", "aes-192-cfb", "aes-256-cfb",
              "rc4-md5", "chacha20-ietf", "xchacha20"}


def parse_ss(link):
    rest = link[len("ss://"):]
    name = ""
    if "#" in rest:
        rest, frag = rest.split("#", 1)
        name = urllib.parse.unquote(frag).strip()
    query = ""
    if "?" in rest:
        rest, query = rest.split("?", 1)
    rest = rest.rstrip("/")
    if "@" not in rest:                                   # legacy: base64(method:password@host:port)
        try:
            rest = _b64decode(rest).decode("utf-8")
        except Exception:
            raise ValueError("ss link is not valid base64")
        if "@" not in rest:
            raise ValueError("ss link has no address")
    userinfo, hostport = rest.rsplit("@", 1)
    userinfo = urllib.parse.unquote(userinfo)
    if ":" not in userinfo:
        try:
            userinfo = _b64decode(userinfo).decode("utf-8")
        except Exception:
            raise ValueError("ss user info is not valid")
    if ":" not in userinfo:
        raise ValueError("ss user info has no method")
    method, password = userinfo.split(":", 1)
    method = method.lower()
    if method not in SS_METHODS:
        raise Unsupported(f"shadowsocks method {method!r} is not supported")
    _, host, port = _split_host_port(hostport)
    params = {"method": method, "password": password}
    plugin = urllib.parse.unquote(_q(urllib.parse.parse_qs(query), "plugin"))
    if plugin:
        pname, _, opts = plugin.partition(";")
        pname = {"simple-obfs": "obfs-local", "obfs": "obfs-local"}.get(pname, pname)
        if pname not in ("obfs-local", "v2ray-plugin"):
            raise Unsupported(f"shadowsocks plugin {pname!r} is not supported")
        params["plugin"] = pname
        if opts:
            params["plugin_opts"] = opts
    return "shadowsocks", host, _port(port), params, name


def _quic_tls(p, host, sni_keys=("sni", "peer"), insecure_keys=("insecure", "allowInsecure", "allow_insecure")):
    tls = {"enabled": True}
    sni = _q(p, *sni_keys)
    if sni or not _is_ip(host):
        tls["server_name"] = sni or host
    if _truthy(_q(p, *insecure_keys)):
        tls["insecure"] = True
    alpn = _q(p, "alpn")
    tls["alpn"] = [a for a in urllib.parse.unquote(alpn).split(",") if a] if alpn else ["h3"]
    return tls


def parse_hysteria2(link):
    if link.lower().startswith("hy2://"):
        link = "hysteria2://" + link[6:]
    auth, host, port, p, name = _std_link_parts(link)
    if not host:
        raise ValueError("missing address")
    params = {"password": auth, "tls": _quic_tls(p, host)}
    obfs = _q(p, "obfs")
    if obfs and obfs != "none":
        if obfs != "salamander":
            raise Unsupported(f"hysteria2 obfs {obfs!r} is not supported")
        params["obfs"] = {"type": "salamander", "password": _q(p, "obfs-password", "obfsPassword")}
    for key, field in (("upmbps", "up_mbps"), ("up", "up_mbps"), ("downmbps", "down_mbps"), ("down", "down_mbps")):
        v = re.sub(r"[^0-9]", "", _q(p, key))
        if v and field not in params:
            params[field] = int(v)
    return "hysteria2", host, _port(re.split(r"[,-]", port or "443")[0]), params, name


def parse_tuic(link):
    user, host, port, p, name = _std_link_parts(link)
    if ":" not in user:
        raise ValueError("tuic link needs uuid:password")
    uuid, password = user.split(":", 1)
    params = {"uuid": uuid, "password": password,
              "congestion_control": _q(p, "congestion_control", "congestion-control", default="bbr"),
              "udp_relay_mode": _q(p, "udp_relay_mode", "udp-relay-mode", default="native"),
              "tls": _quic_tls(p, host, ("sni",))}
    return "tuic", host, _port(port), params, name


def parse_hysteria(link):
    _, host, port, p, name = _std_link_parts(link)
    proto = _q(p, "protocol", default="udp")
    if proto not in ("udp", ""):
        raise Unsupported(f"hysteria protocol {proto!r} is not supported")
    params = {"up_mbps": int(re.sub(r"[^0-9]", "", _q(p, "upmbps", "up", default="10")) or 10),
              "down_mbps": int(re.sub(r"[^0-9]", "", _q(p, "downmbps", "down", default="50")) or 50)}
    auth = _q(p, "auth", "auth_str")
    if auth:
        params["auth_str"] = auth
    obfs = _q(p, "obfsParam", "obfs")
    if obfs and obfs != "none":
        params["obfs"] = obfs
    tls = _quic_tls(p, host, ("peer", "sni"), ("insecure",))
    if not _q(p, "alpn"):
        tls.pop("alpn", None)
    params["tls"] = tls
    return "hysteria", host, _port(port), params, name


def parse_socks(link):
    sp = urllib.parse.urlsplit(link)
    user, host, port = _split_host_port(sp.netloc)
    params = {"version": "5"}
    if user:
        if ":" not in user:
            try:
                user = _b64decode(user).decode("utf-8")
            except Exception:
                pass
        u, _, pw = user.partition(":")
        params["username"] = u
        if pw:
            params["password"] = pw
    return "socks", host, _port(port), params, urllib.parse.unquote(sp.fragment).strip()


LINK_PARSERS = {
    "vless": parse_vless, "vmess": parse_vmess, "trojan": parse_trojan, "ss": parse_ss,
    "hysteria2": parse_hysteria2, "hy2": parse_hysteria2, "tuic": parse_tuic,
    "hysteria": parse_hysteria, "socks": parse_socks, "socks5": parse_socks,
}


def parse_link(link):
    scheme = link.split("://", 1)[0].lower()
    if scheme not in LINK_PARSERS:
        raise Unsupported(f"{scheme}:// links are not supported")
    proto, host, port, params, name = LINK_PARSERS[scheme](link)
    return make_server(proto, host, port, params, name)


def make_server(proto, host, port, params, name):
    host = str(host).strip()
    if not host:
        raise ValueError("missing server address")
    name = re.sub(r"\s+", " ", (name or f"{proto} {host}:{port}")).strip()
    return {"name": name, "protocol": proto, "address": host, "port": int(port),
            "params": params, "country": detect_country(name)}


# ---- Clash YAML ------------------------------------------------------------------------


def clash_to_server(px):
    if not isinstance(px, dict):
        raise ValueError("proxy entry is not a mapping")
    t = str(px.get("type", "")).lower()
    name = str(px.get("name", "")).strip()
    host = str(px.get("server", "")).strip()
    port = px.get("port")
    sni = px.get("servername") or px.get("sni") or ""
    alpn = px.get("alpn")
    if t == "ss":
        method = str(px.get("cipher", "")).lower()
        if method not in SS_METHODS:
            raise Unsupported(f"shadowsocks method {method!r} is not supported")
        params = {"method": method, "password": str(px.get("password", ""))}
        if px.get("plugin"):
            po = px.get("plugin-opts") or {}
            if px["plugin"] != "obfs":
                raise Unsupported(f"shadowsocks plugin {px['plugin']!r} is not supported")
            params["plugin"] = "obfs-local"
            params["plugin_opts"] = "obfs=" + str(po.get("mode", "http")) + (";obfs-host=" + str(po["host"]) if po.get("host") else "")
        return make_server("shadowsocks", host, _port(port), params, name)
    if t in ("hysteria2", "tuic"):
        q = {"sni": sni, "insecure": "1" if px.get("skip-cert-verify") else "",
             "alpn": ",".join(alpn) if isinstance(alpn, list) else (alpn or "")}
        tls = _quic_tls({k: v for k, v in q.items() if v}, host, ("sni",), ("insecure",))
        if t == "hysteria2":
            params = {"password": str(px.get("password", "")), "tls": tls}
            if px.get("obfs"):
                params["obfs"] = {"type": "salamander", "password": str(px.get("obfs-password", ""))}
            for k, f in (("up", "up_mbps"), ("down", "down_mbps")):
                v = re.sub(r"[^0-9]", "", str(px.get(k, "")))
                if v:
                    params[f] = int(v)
        else:
            params = {"uuid": str(px.get("uuid", "")), "password": str(px.get("password", "")),
                      "congestion_control": str(px.get("congestion-controller", "bbr")),
                      "udp_relay_mode": str(px.get("udp-relay-mode", "native")), "tls": tls}
        return make_server(t, host, _port(port), params, name)
    if t == "socks5":
        params = {"version": "5"}
        if px.get("username"):
            params["username"] = str(px["username"])
            params["password"] = str(px.get("password", ""))
        return make_server("socks", host, _port(port), params, name)
    if t == "vmess":
        params = {"uuid": str(px.get("uuid", "")), "security": str(px.get("cipher", "auto")),
                  "alter_id": int(px.get("alterId", 0) or 0)}
    elif t == "vless":
        params = {"uuid": str(px.get("uuid", "")), "packet_encoding": "xudp"}
        if px.get("flow"):
            params["flow"] = str(px["flow"])
    elif t == "trojan":
        params = {"password": str(px.get("password", ""))}
    else:
        raise Unsupported(f"Clash proxy type {t!r} is not supported")
    if not params.get("uuid", "x") or not params.get("password", "x"):
        raise ValueError("missing uuid or password")
    tls_on = bool(px.get("tls")) or t == "trojan"
    q = {"security": "tls" if tls_on else "none", "sni": sni, "fp": px.get("client-fingerprint", ""),
         "allowInsecure": "1" if px.get("skip-cert-verify") else "",
         "alpn": ",".join(alpn) if isinstance(alpn, list) else (alpn or "")}
    ro = px.get("reality-opts") or {}
    if ro:
        q.update(security="reality", pbk=ro.get("public-key", ""), sid=ro.get("short-id", ""))
    tls = _tls({k: v for k, v in q.items() if v}, host)
    if tls:
        params["tls"] = tls
    net = str(px.get("network", "tcp"))
    host_header = path = service = ""
    if net == "ws":
        ws = px.get("ws-opts") or {}
        path = str(ws.get("path", "/"))
        host_header = str((ws.get("headers") or {}).get("Host", ""))
        if ws.get("max-early-data"):
            path += ("&" if "?" in path else "?") + "ed=" + str(ws.get("max-early-data"))
    elif net == "grpc":
        service = str((px.get("grpc-opts") or {}).get("grpc-service-name", ""))
    elif net == "h2":
        h2 = px.get("h2-opts") or {}
        path = str(h2.get("path", ""))
        host_header = ",".join(h2.get("host") or [])
    elif net == "http":
        raise Unsupported("TCP with HTTP header obfuscation is not supported by sing-box")
    tr = _transport(net, {}, host_header, path, service)
    if tr:
        params["transport"] = tr
    return make_server(t, host, _port(port), params, name)


def parse_clash(text, result):
    try:
        import yaml
    except ImportError:
        raise VpnError("need_yaml")
    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError as e:
        mark = getattr(e, "problem_mark", None)
        raise VpnError("bad_yaml", f"line {mark.line + 1}" if mark else type(e).__name__)
    proxies = data.get("proxies") if isinstance(data, dict) else None
    if not isinstance(proxies, list):
        raise VpnError("bad_yaml", "no 'proxies' list")
    for i, px in enumerate(proxies, 1):
        label = str(px.get("name", "")) if isinstance(px, dict) else ""
        try:
            result["servers"].append(clash_to_server(px))
        except (Unsupported, ValueError, TypeError) as e:
            result["errors"].append({"item": i, "name": label, "error": str(e)})


# ---- sing-box JSON ---------------------------------------------------------------------

SINGBOX_SKIP = {"direct", "block", "dns", "selector", "urltest"}
SINGBOX_KNOWN = {"vless", "vmess", "trojan", "shadowsocks", "hysteria2", "hysteria", "tuic", "socks", "http",
                 "anytls", "ssh", "wireguard"}


def parse_singbox(data, result):
    outbounds = data.get("outbounds") if isinstance(data, dict) else data
    if not isinstance(outbounds, list):
        raise VpnError("bad_json", "no 'outbounds' list")
    for i, ob in enumerate(outbounds, 1):
        if not isinstance(ob, dict):
            result["errors"].append({"item": i, "name": "", "error": "outbound is not an object"})
            continue
        t = str(ob.get("type", ""))
        if t in SINGBOX_SKIP:
            continue
        label = str(ob.get("tag", ""))
        if t not in SINGBOX_KNOWN:
            result["errors"].append({"item": i, "name": label, "error": f"outbound type {t!r} is not supported"})
            continue
        if ob.get("detour"):
            result["errors"].append({"item": i, "name": label, "error": "chained outbounds (detour) are not supported"})
            continue
        try:
            params = {k: v for k, v in ob.items() if k not in ("type", "tag", "server", "server_port")}
            result["servers"].append(make_server(t, ob.get("server", ""), _port(ob.get("server_port")), params, label))
        except (ValueError, TypeError) as e:
            result["errors"].append({"item": i, "name": label, "error": str(e)})


# ---- whole subscription ----------------------------------------------------------------


def _looks_like_base64(text):
    compact = re.sub(r"\s+", "", text)
    return len(compact) >= 8 and re.fullmatch(r"[A-Za-z0-9+/=_-]+", compact) is not None


def parse_subscription(text, _depth=0):
    """Subscription text -> {"format", "servers", "errors"}. Raises VpnError when nothing is usable."""
    result = {"format": "", "servers": [], "errors": []}
    text = (text or "").strip().lstrip("﻿").strip()
    if not text:
        raise VpnError("empty")
    head = text[:400].lower()
    if head.startswith("<!doctype") or head.startswith("<html") or "<html" in head:
        raise VpnError("html")
    if text[0] in "{[":
        try:
            data = json.loads(text)
        except ValueError as e:
            raise VpnError("bad_json", str(e).split(":")[0])
        result["format"] = "sing-box"
        parse_singbox(data, result)
    elif re.search(r"(?m)^proxies\s*:", text):
        result["format"] = "clash"
        parse_clash(text, result)
    elif "://" in text:
        result["format"] = "links"
        for i, line in enumerate(text.splitlines(), 1):
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("//"):
                continue
            if "://" not in line:
                result["errors"].append({"item": i, "name": "", "error": "not a link"})
                continue
            scheme = line.split("://", 1)[0].lower()
            try:
                result["servers"].append(parse_link(line))
            except (Unsupported, ValueError, TypeError, KeyError, IndexError) as e:
                frag = urllib.parse.unquote(line.split("#", 1)[1]) if "#" in line else ""
                result["errors"].append({"item": i, "name": frag, "error": f"{scheme}: {e}"})
    elif _depth == 0 and _looks_like_base64(text):
        try:
            decoded = _b64decode(text).decode("utf-8")
        except Exception:
            raise VpnError("unknown_format")
        inner = parse_subscription(decoded, _depth + 1)
        inner["format"] = "base64-" + inner["format"]
        return inner
    else:
        raise VpnError("unknown_format")
    if not result["servers"]:
        raise VpnError("no_servers", "; ".join(e["error"] for e in result["errors"][:3]))
    assign_tags(result["servers"])
    return result


def assign_tags(servers):
    used = set()
    for s in servers:
        base = s["name"][:64] or s["protocol"]
        if base in ("proxy", "direct"):
            base += " server"
        tag, n = base, 1
        while tag in used:
            n += 1
            tag = f"{base} #{n}"
        used.add(tag)
        s["tag"] = tag
    return servers


# ---- sing-box config -------------------------------------------------------------------


def build_config(servers, settings, mode="proxy"):
    """mode "proxy": mixed inbound on 127.0.0.1 + Clash API; "probe": no inbounds (delay tests only)."""
    tags = [s["tag"] for s in servers]
    if not tags:
        raise VpnError("no_servers")
    default = settings.get("selected") if settings.get("selected") in tags else tags[0]
    outbounds = [{"type": "selector", "tag": "proxy", "outbounds": tags, "default": default,
                  "interrupt_exist_connections": True}]
    for s in servers:
        ob = {"type": s["protocol"], "tag": s["tag"], "server": s["address"], "server_port": s["port"]}
        ob.update(s.get("params") or {})
        outbounds.append(ob)
    outbounds.append({"type": "direct", "tag": "direct"})
    port = settings["probePort"] if mode == "probe" else settings["apiPort"]
    cfg = {
        "log": {"level": "warn", "timestamp": True},
        "inbounds": [],
        "outbounds": outbounds,
        "route": {"final": "proxy"},
        "experimental": {"clash_api": {"external_controller": f"127.0.0.1:{port}", "secret": settings["secret"]}},
    }
    if mode == "proxy":
        cfg["inbounds"].append({"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1",
                                "listen_port": settings["proxyPort"]})
    return cfg


def _strip_ansi(s):
    return re.sub(r"\x1b\[[0-9;]*m", "", s)


def singbox_check(cfg, binary=None):
    """(ok, detail). Raises VpnError("no_singbox") when sing-box is missing."""
    binary = binary or singbox_bin()
    if not binary:
        raise VpnError("no_singbox")
    fd, path = tempfile.mkstemp(prefix="serp-vpn-check-", suffix=".json")    # mode 600
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(cfg, f)
        p = subprocess.run([binary, "check", "-c", path], capture_output=True, text=True, timeout=30)
        detail = _strip_ansi((p.stderr or p.stdout or "").strip().replace(path, "config.json"))
        return p.returncode == 0, detail[-600:]
    except (OSError, subprocess.SubprocessError) as e:
        return False, type(e).__name__
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass


def singbox_version():
    binary = singbox_bin()
    if not binary:
        return ""
    try:
        out = subprocess.run([binary, "version"], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    m = re.search(r"version\s+(\S+)", out)
    return m.group(1) if m else ""


# ---- sources and download --------------------------------------------------------------


def unwrap_source(text):
    """Import links of other clients -> the subscription URL inside; plain text stays."""
    t = (text or "").strip()
    if t.lower().startswith("happ://"):
        raise VpnError("happ_encrypted")
    m = re.match(r"(?i)^(?:hiddify|sing-box|clash|clashmeta|v2rayng|streisand|nekobox)://[^?#]*[?&]url=([^&#]+)", t)
    if m:
        return urllib.parse.unquote(m.group(1))
    m = re.match(r"(?i)^hiddify://import/(https?://\S+?)(?:#.*)?$", t)
    if m:
        return m.group(1)
    return t


def is_url(text):
    return re.match(r"(?i)^https?://\S+$", (text or "").strip()) is not None


def fetch(url, settings):
    """(text, info). info: title / traffic / expiry from the provider's headers. Never echoes the URL."""
    req = urllib.request.Request(url, headers={"User-Agent": settings.get("userAgent") or DEFAULT_SETTINGS["userAgent"],
                                               "Accept": "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            data = r.read(5 * 1024 * 1024 + 1)
            headers = {k.lower(): v for k, v in r.headers.items()}
    except urllib.error.HTTPError as e:
        raise VpnError("fetch_http", e.code)
    except urllib.error.URLError as e:
        reason = getattr(e, "reason", None)
        detail = reason if isinstance(reason, str) else (getattr(reason, "strerror", None) or type(reason).__name__)
        raise VpnError("fetch_failed", detail)
    except (OSError, ValueError) as e:
        raise VpnError("fetch_failed", type(e).__name__)
    if len(data) > 5 * 1024 * 1024:
        raise VpnError("too_large")
    info = {}
    for part in headers.get("subscription-userinfo", "").split(";"):
        k, _, v = part.strip().partition("=")
        if k in ("upload", "download", "total", "expire") and v.strip().isdigit():
            info[k] = int(v.strip())
    title = headers.get("profile-title", "")
    if title.startswith("base64:"):
        try:
            title = base64.b64decode(title[7:]).decode("utf-8")
        except Exception:
            title = ""
    if title:
        info["title"] = title[:80]
    return data.decode("utf-8", errors="replace"), info


def load_source_text(source, settings):
    src = unwrap_source(source)
    if is_url(src):
        return fetch(src, settings)
    return src, {}


# ---- update ----------------------------------------------------------------------------


def server_summary(s):
    c = s.get("country", "")
    return {"tag": s["tag"], "name": s["name"], "protocol": s["protocol"], "address": s["address"],
            "port": s["port"], "country": c, "countryName": country_name(c), "flag": flag(c)}


def _source_text():
    return read_text(os.path.join(config_dir(), "source")).strip()


def update(auto=False, prepared=None, restart=True):
    source = _source_text()
    if not source:                          # nothing is created for users who never use the VPN
        if auto:
            return {"ok": True, "skipped": "no_source"}
        raise VpnError("no_source")
    settings = load_settings()
    last = read_json(os.path.join(state_dir(), "last_update.json"), {})
    if auto and not singbox_bin():
        return {"ok": True, "skipped": "no_singbox"}
    if auto and last.get("ok") and time.time() - float(last.get("time", 0)) < settings["updateHours"] * 3600:
        return {"ok": True, "skipped": "fresh"}
    entry = {"time": time.time(), "ok": False}
    try:
        if prepared is None:
            text, info = load_source_text(source, settings)
            parsed = parse_subscription(text)
            cfg = build_config(parsed["servers"], settings)
            ok, detail = singbox_check(cfg)
            if not ok:
                raise VpnError("check_failed", detail)
        else:
            parsed, info, cfg = prepared
    except VpnError as e:
        entry.update(e.as_dict())
        entry["keptOld"] = os.path.exists(os.path.join(state_dir(), "config.json"))
        if entry["keptOld"]:
            entry["message"] += " " + msg("kept_old")
        entry["servers"] = last.get("servers", 0)
        write_private(os.path.join(state_dir(), "last_update.json"), json.dumps(entry, ensure_ascii=False))
        _record_sub_update(entry)
        raise
    # sing-box accepted it: only now replace the working files.
    write_private(os.path.join(state_dir(), "servers.json"), json.dumps(parsed["servers"], ensure_ascii=False))
    write_private(os.path.join(state_dir(), "config.json"), json.dumps(cfg, indent=2, ensure_ascii=False))
    entry.update(ok=True, format=parsed["format"], servers=len(parsed["servers"]),
                 skippedCount=len(parsed["errors"]), skipped=parsed["errors"][:20], info=info)
    write_private(os.path.join(state_dir(), "last_update.json"), json.dumps(entry, ensure_ascii=False))
    _record_sub_update(entry)
    if restart and vpn_running():
        try:
            restart_proxy()
        except VpnError as e:
            entry["restartError"] = e.as_dict()["message"]
    return entry


# ---- sing-box process ------------------------------------------------------------------


def pid_path():
    return os.path.join(state_dir(), "sing-box.pid")


def _pid_alive(pid):
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    if os.path.isdir("/proc"):
        return "sing-box" in read_text(f"/proc/{pid}/cmdline", "")
    return True


def running_pid():
    try:
        pid = int(read_text(pid_path(), "").strip())
    except ValueError:
        return 0
    return pid if _pid_alive(pid) else 0


def is_running():
    return running_pid() > 0


def _port_free(port):
    import socket
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


def api(settings, method, path, body=None, port=None, timeout=6):
    """Clash API of our own sing-box on 127.0.0.1 (control only; delay tests are run by sing-box)."""
    url = f"http://127.0.0.1:{port or settings['apiPort']}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Authorization": "Bearer " + settings["secret"],
                                          "Content-Type": "application/json"})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))   # never through a proxy
    with opener.open(req, timeout=timeout) as r:
        raw = r.read()
    return json.loads(raw) if raw.strip() else {}


def _wait_api(settings, port, proc=None, seconds=6.0):
    deadline = time.time() + seconds
    last = "timeout"
    while time.time() < deadline:
        if proc is not None and proc.poll() is not None:
            return False, "exited"
        try:
            api(settings, "GET", "/version", port=port, timeout=1)
            return True, ""
        except Exception as e:
            last = type(e).__name__
            time.sleep(0.15)
    return False, last


def _log_tail(path, n=6):
    lines = read_text(path, "").strip().splitlines()[-n:]
    return _strip_ansi(" | ".join(lines))[-500:]


def _die_with_parent():
    """Child setup for the short-lived probe: SIGTERM when this script dies (Linux)."""
    try:
        import ctypes
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)   # PR_SET_PDEATHSIG
    except Exception:
        pass


def _popen(args, probe=False, **kw):
    if os.name == "posix":
        if probe:
            kw["preexec_fn"] = _die_with_parent
        else:
            kw["start_new_session"] = True  # the proxy keeps running when the shell restarts
    return subprocess.Popen(args, stdin=subprocess.DEVNULL, close_fds=True, **kw)


def connect():
    settings = load_settings()
    if settings["mode"] == "tun":
        return tun_connect()
    if tun_state() in ("active", "activating"):     # switched back to proxy: free the ports
        tun_disconnect()
    cfg_path = os.path.join(state_dir(), "config.json")
    if not os.path.exists(cfg_path):
        raise VpnError("no_config" if _source_text() else "no_source")
    binary = singbox_bin()
    if not binary:
        raise VpnError("no_singbox")
    if is_running():
        return status()
    for port in (settings["proxyPort"], settings["apiPort"]):
        if not _port_free(port):
            raise VpnError("port_busy", port)
    log_path = os.path.join(state_dir(), "sing-box.log")
    write_private(log_path, "")
    with open(log_path, "a", encoding="utf-8") as log:
        proc = _popen([binary, "run", "-c", cfg_path], stdout=log, stderr=log)
    write_private(pid_path(), str(proc.pid))
    ok, why = _wait_api(settings, settings["apiPort"], proc)
    if not ok:
        try:
            proc.terminate()
            proc.wait(3)
        except (OSError, subprocess.SubprocessError):
            pass
        try:
            os.unlink(pid_path())
        except OSError:
            pass
        raise VpnError("start_failed", _log_tail(log_path) or why)
    return status()


def disconnect():
    """Stops whatever runs: the user proxy and, if active, the TUN service."""
    _proxy_disconnect()
    tun_disconnect()
    return status()


def _proxy_disconnect():
    pid = running_pid()
    if pid:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
        for _ in range(60):
            if not _pid_alive(pid):
                break
            time.sleep(0.05)
        else:
            try:
                os.kill(pid, getattr(signal, "SIGKILL", signal.SIGTERM))
            except OSError:
                pass
    try:
        os.unlink(pid_path())
    except OSError:
        pass


def restart_proxy():
    """Re-apply after an update: the user proxy is restarted, TUN gets the new config."""
    if tun_state() in ("active", "activating", "reloading"):
        return tun_connect()
    disconnect()
    return connect()


# ---- stage 2: TUN through the serpantinum-vpn system service -----------------------------

UNIT = "serpantinum-vpn.service"
TUN_IFACE = "serp-tun0"


def helper_path():
    return os.environ.get("SERP_VPN_HELPER", "/usr/libexec/serpantinum/serp-vpn-root")


def unit_path():
    return os.environ.get("SERP_VPN_UNIT_FILE", "/etc/systemd/system/" + UNIT)


def _tool(env, name):
    v = os.environ.get(env)
    if v is not None:
        return v
    return shutil.which(name) or ""


def _run(args, input_text=None, timeout=30):
    """(returncode, stdout, stderr); returncode None on timeout, 127 when it cannot start."""
    try:
        p = subprocess.run(args, input=input_text, capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=timeout,
                           stdin=None if input_text is not None else subprocess.DEVNULL)
        return p.returncode, p.stdout or "", p.stderr or ""
    except subprocess.TimeoutExpired:
        return None, "", ""
    except OSError as e:
        return 127, "", type(e).__name__


def tun_installed():
    return os.path.isfile(helper_path()) and os.path.isfile(unit_path()) and bool(_tool("SERP_VPN_SYSTEMCTL", "systemctl"))


def tun_state():
    """systemctl is-active: active, activating, deactivating, failed, inactive; "" without systemd."""
    systemctl = _tool("SERP_VPN_SYSTEMCTL", "systemctl")
    if not systemctl or not os.path.isfile(unit_path()):
        return ""
    rc, out, _ = _run([systemctl, "is-active", UNIT], timeout=5)
    return (out.strip().splitlines() or [""])[0] if rc is not None else "deactivating"


def vpn_running():
    return is_running() or tun_state() == "active"


def _auth_denied(text):
    t = (text or "").lower()
    return any(k in t for k in ("not authorized", "access denied", "interactive authentication required",
                                "authentication is required", "permission denied", "request dismissed"))


def tun_payload(cfg, settings):
    """What the root helper gets: the server outbounds and our ports/secret. Never the link."""
    obs = [o for o in (cfg.get("outbounds") or [])
           if isinstance(o, dict) and o.get("type") not in ("selector", "urltest", "direct", "block", "dns")]
    return {"outbounds": obs, "secret": settings["secret"], "apiPort": settings["apiPort"],
            "proxyPort": settings["proxyPort"], "selected": settings.get("selected", "")}


def _helper(action, input_text=None, timeout=120):
    pkexec = _tool("SERP_VPN_PKEXEC", "pkexec")
    if not pkexec:
        raise VpnError("not_authorized", "pkexec")
    rc, out, err = _run([pkexec, helper_path(), action], input_text=input_text, timeout=timeout)
    if rc is None:
        raise VpnError("not_authorized", "timeout")
    try:
        data = json.loads(out.strip().splitlines()[-1]) if out.strip() else {}
    except ValueError:
        data = {}
    if rc in (126, 127) and not data:          # pkexec: dismissed / not authorized / cannot run
        raise VpnError("not_authorized", _strip_ansi(err.strip())[-200:])
    return rc, data, err


def journal_tail(n=6):
    journalctl = _tool("SERP_VPN_JOURNALCTL", "journalctl")
    if not journalctl:
        return ""
    rc, out, _ = _run([journalctl, "-u", UNIT, "-n", str(n), "-o", "cat", "--no-pager"], timeout=5)
    return _strip_ansi(out.strip())[-500:] if rc == 0 else ""


def tun_connect():
    settings = load_settings()
    cfg = read_json(os.path.join(state_dir(), "config.json"), None)
    if not isinstance(cfg, dict):
        raise VpnError("no_config" if _source_text() else "no_source")
    if not tun_installed():
        raise VpnError("tun_not_installed")
    if is_running():                     # the user proxy holds the same ports
        _proxy_disconnect()
    rc, data, err = _helper("apply", json.dumps(tun_payload(cfg, settings)))     # ASCII: no locale issues
    if not data.get("ok"):
        e = data.get("error") or {}
        code = e.get("code", "")
        if code == "no_singbox":
            raise VpnError("no_singbox_root")
        if code == "old_singbox":
            raise VpnError("old_singbox", e.get("detail", ""))
        raise VpnError("tun_apply_failed", e.get("detail") or _strip_ansi(err.strip())[-300:] or f"exit {rc}")
    write_private(os.path.join(state_dir(), "tun_applied"), "1\n")     # `clear` also wipes /etc
    systemctl = _tool("SERP_VPN_SYSTEMCTL", "systemctl")
    _run([systemctl, "reset-failed", UNIT], timeout=10)
    rc, out, err = _run([systemctl, "restart", UNIT], timeout=40)
    if rc is None:
        raise VpnError("service_failed", "timeout")
    if rc != 0:
        if _auth_denied(err):
            raise VpnError("not_authorized", _strip_ansi(err.strip())[-200:])
        raise VpnError("service_failed", journal_tail() or _strip_ansi(err.strip())[-300:])
    deadline = time.time() + 10
    while time.time() < deadline:
        try:
            api(settings, "GET", "/version", timeout=1)
            break
        except Exception:
            if tun_state() in ("failed", "inactive"):
                raise VpnError("service_failed", journal_tail() or "-")
            time.sleep(0.25)
    else:
        raise VpnError("service_failed", journal_tail() or "Clash API")
    out = status()
    if data.get("skipped"):
        out["tunSkipped"] = len(data["skipped"])
    return out


def tun_disconnect():
    systemctl = _tool("SERP_VPN_SYSTEMCTL", "systemctl")
    if not systemctl or tun_state() in ("", "inactive", "failed"):
        return
    rc, _, err = _run([systemctl, "stop", UNIT], timeout=20)
    if rc is None or tun_state() == "deactivating":
        raise VpnError("stop_timeout")
    if rc != 0 and _auth_denied(err):
        raise VpnError("not_authorized", _strip_ansi(err.strip())[-200:])


def force_off():
    """Emergency off: works when the service hangs or sing-box left routes behind."""
    steps = {}
    _proxy_disconnect()
    steps["proxy"] = "stopped"
    systemctl = _tool("SERP_VPN_SYSTEMCTL", "systemctl")
    if systemctl and os.path.isfile(unit_path()):
        rc, _, _ = _run([systemctl, "kill", "--signal=SIGKILL", UNIT], timeout=10)
        steps["kill"] = "ok" if rc == 0 else ("timeout" if rc is None else "not running")
        rc, _, _ = _run([systemctl, "stop", UNIT], timeout=15)
        steps["stop"] = "ok" if rc == 0 else ("timeout" if rc is None else f"exit {rc}")
        _run([systemctl, "reset-failed", UNIT], timeout=10)
    out_error = None
    if tun_installed():
        try:
            rc, data, err = _helper("cleanup", timeout=60)
            steps["cleanup"] = "ok" if data.get("ok") else f"exit {rc}"
            if not data.get("ok"):
                out_error = msg("cleanup_failed", _strip_ansi(err.strip())[-200:] or f"exit {rc}")
        except VpnError as e:
            steps["cleanup"] = e.code
            out_error = msg("cleanup_failed", e.as_dict()["message"])
    out = status()
    out["forced"] = steps
    if out_error:
        out["error"] = out_error
    return out


def set_mode(mode):
    if mode not in ("proxy", "tun"):
        raise VpnError("bad_mode", mode)
    settings = load_settings()
    was = vpn_running()
    if mode == "tun" and not tun_installed():
        raise VpnError("tun_not_installed")
    if settings["mode"] != mode:
        if was:
            disconnect()
        settings["mode"] = mode
        save_settings(settings)
        if was:
            return connect()
    return status()


# -- warnings: DNS and other VPNs (pure parsers + one collector; nothing here needs root) --

VPN_IFACE_PREFIXES = ("wg", "tun", "tap", "ppp", "nordlynx", "proton", "mullvad", "tailscale", "zt",
                      "utun", "ipsec", "vti", "amn", "warp", "CloudflareWARP", "outline-tun")
VPN_PROCS = {"openvpn": "OpenVPN", "openconnect": "OpenConnect", "wireguard-go": "WireGuard",
             "xray": "Xray", "v2ray": "V2Ray", "mihomo": "Mihomo (Clash)", "clash": "Clash",
             "clash-meta": "Clash", "nekoray": "NekoRay", "nekobox": "NekoBox", "hiddify": "Hiddify",
             "hiddifycli": "Hiddify", "happ": "Happ", "v2rayn": "v2rayN", "amneziavpn": "AmneziaVPN",
             "amneziawg-go": "AmneziaWG", "warp-svc": "Cloudflare WARP", "nordvpnd": "NordVPN",
             "mullvad-daemon": "Mullvad", "expressvpnd": "ExpressVPN", "protonvpn": "Proton VPN",
             "outline-ss-local": "Outline", "throne": "Throne"}


def iface_conflicts(names):
    """VPN-like interfaces other than ours. Tailscale is reported separately."""
    found = []
    for n in sorted(set(names)):
        if n in (TUN_IFACE, "lo", "tunl0", "ip6tnl0") or n.startswith("tailscale"):
            continue                     # tunl0/ip6tnl0: kernel ipip fallback devices, not VPNs
        if n.lower().startswith(tuple(p.lower() for p in VPN_IFACE_PREFIXES)):
            found.append(n)
    return found


def proc_conflicts(comms):
    """Names of other VPN programs among process names (/proc/*/comm)."""
    return sorted({VPN_PROCS[c.strip().lower()] for c in comms if c.strip().lower() in VPN_PROCS})


def parse_nmcli_active(text):
    """`nmcli -t -f NAME,TYPE connection show --active` -> names of VPN / WireGuard connections."""
    out = []
    for line in (text or "").splitlines():
        if not line.strip():
            continue
        parts = re.split(r"(?<!\\):", line)
        if len(parts) < 2:
            continue
        name, typ = parts[0].replace("\\:", ":"), parts[-1].strip().lower()
        if typ in ("vpn", "wireguard") or typ.endswith("-vpn"):
            out.append(name)
    return out


def parse_resolvectl_dot(text):
    """True when `resolvectl status` shows DNS-over-TLS on (+DNSOverTLS / DNSOverTLS=yes|opportunistic)."""
    t = text or ""
    return bool(re.search(r"\+DNSOverTLS\b", t) or re.search(r"DNSOverTLS\s*[=:]\s*(yes|opportunistic)", t, re.I))


def dns_checks(resolv_target, resolved_active, dot):
    out = []
    if not resolved_active:
        out.append(("dns_no_resolved", ""))
    elif resolv_target and "/run/systemd/resolve/" not in resolv_target:
        out.append(("dns_not_stub", resolv_target))
    if resolved_active and dot:
        out.append(("dns_dot", ""))
    return out


def build_checks(ifaces, comms, nm_vpns, resolv_target, resolved_active, dot):
    """List of {code, level, message}. "warn" for other VPNs, "info" for DNS notes."""
    items = []
    if "tailscale0" in ifaces or any(c.strip() == "tailscaled" for c in comms):
        items.append(("conflict_tailscale", "", "warn"))
    others = iface_conflicts(ifaces)
    if others:
        items.append(("conflict_iface", ", ".join(others), "warn"))
    procs = proc_conflicts(comms)
    if procs:
        items.append(("conflict_proc", ", ".join(procs), "warn"))
    if nm_vpns:
        items.append(("conflict_nm", ", ".join(nm_vpns), "warn"))
    for code, detail in dns_checks(resolv_target, resolved_active, dot):
        items.append((code, detail, "info"))
    return [{"code": c, "level": lvl, "message": msg(c, d)} for c, d, lvl in items]


def collect_checks():
    """Reads /sys, /proc, /etc/resolv.conf, nmcli and systemctl; silent where they do not exist."""
    try:
        ifaces = os.listdir("/sys/class/net")
    except OSError:
        ifaces = []
    comms = []
    if os.path.isdir("/proc"):
        for pid in os.listdir("/proc"):
            if pid.isdigit():
                c = read_text(f"/proc/{pid}/comm", "").strip()
                if c:
                    comms.append(c)
    nm_vpns = []
    nmcli = _tool("SERP_VPN_NMCLI", "nmcli")
    if nmcli:
        rc, out, _ = _run([nmcli, "-t", "-f", "NAME,TYPE", "connection", "show", "--active"], timeout=4)
        nm_vpns = parse_nmcli_active(out) if rc == 0 else []
    resolv_target = os.path.realpath("/etc/resolv.conf") if os.path.exists("/etc/resolv.conf") else ""
    resolved_active, dot = False, False
    systemctl = _tool("SERP_VPN_SYSTEMCTL", "systemctl")
    if systemctl:
        rc, out, _ = _run([systemctl, "is-active", "systemd-resolved.service"], timeout=4)
        resolved_active = rc == 0 and out.strip() == "active"
    if resolved_active:
        resolvectl = _tool("SERP_VPN_RESOLVECTL", "resolvectl")
        if resolvectl:
            rc, out, _ = _run([resolvectl, "status"], timeout=4)
            dot = rc == 0 and parse_resolvectl_dot(out)
    if not ifaces and not comms and not systemctl:      # not Linux: nothing to say
        return []
    return build_checks(ifaces, comms, nm_vpns, resolv_target, resolved_active, dot)


def _servers():
    data = read_json(os.path.join(state_dir(), "servers.json"), [])
    return data if isinstance(data, list) else []


def select(tag):
    settings = load_settings()
    if tag not in [s.get("tag") for s in _servers()]:
        raise VpnError("unknown_server", tag)
    settings["selected"] = tag
    save_settings(settings)
    cfg_path = os.path.join(state_dir(), "config.json")
    cfg = read_json(cfg_path, None)
    if isinstance(cfg, dict):           # same server after a reconnect / restart
        for ob in cfg.get("outbounds", []):
            if ob.get("tag") == "proxy" and ob.get("type") == "selector":
                ob["default"] = tag
        write_private(cfg_path, json.dumps(cfg, indent=2, ensure_ascii=False))
    if vpn_running():
        try:
            api(settings, "PUT", "/proxies/proxy", {"name": tag})
        except Exception as e:
            raise VpnError("api_failed", type(e).__name__)
    return status()


def ping():
    """Delay of every server, measured by sing-box itself (Clash API group delay test)."""
    settings = load_settings()
    servers = _servers()
    if not servers:
        raise VpnError("no_config" if _source_text() else "no_source")
    url = urllib.parse.quote(settings["testUrl"], safe="")
    probe = None
    port = settings["apiPort"]
    if not vpn_running():
        binary = singbox_bin()
        if not binary:
            raise VpnError("no_singbox")
        port = settings["probePort"]
        if not _port_free(port):
            raise VpnError("port_busy", port)
        probe_path = os.path.join(state_dir(), "probe.json")
        write_private(probe_path, json.dumps(build_config(servers, settings, mode="probe")))
        probe = _popen([binary, "run", "-c", probe_path], probe=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        if probe is not None:
            ok, why = _wait_api(settings, port, probe)
            if not ok:
                raise VpnError("api_failed", why)
        try:
            delays = api(settings, "GET", f"/group/proxy/delay?url={url}&timeout=5000", port=port, timeout=15)
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise VpnError("api_failed", f"HTTP {e.code}")
            delays = {}
            for s in servers:            # older sing-box without group delay: one request per server
                try:
                    r = api(settings, "GET", f"/proxies/{urllib.parse.quote(s['tag'], safe='')}/delay"
                                             f"?url={url}&timeout=5000", port=port, timeout=8)
                    delays[s["tag"]] = int(r.get("delay", 0))
                except Exception:
                    delays[s["tag"]] = 0
        except VpnError:
            raise
        except Exception as e:
            raise VpnError("api_failed", type(e).__name__)
    finally:
        if probe is not None:
            probe.terminate()
            try:
                probe.wait(3)
            except subprocess.TimeoutExpired:
                probe.kill()
            try:
                os.unlink(os.path.join(state_dir(), "probe.json"))
            except OSError:
                pass
    result = {}
    for s in servers:
        try:
            result[s["tag"]] = max(0, int(delays.get(s["tag"], 0) or 0))
        except (TypeError, ValueError):
            result[s["tag"]] = 0
    write_private(os.path.join(state_dir(), "pings.json"), json.dumps({"time": time.time(), "delays": result}, ensure_ascii=False))
    return {"ok": True, "delays": result}


def status():
    settings = load_settings_readonly()     # read-only: status never creates files
    has_source = bool(_source_text())
    servers = _servers()
    tags = [s.get("tag") for s in servers]
    last = read_json(os.path.join(state_dir(), "last_update.json"), {})
    tstate = tun_state()
    running = is_running() or tstate == "active"
    current = settings["selected"] if settings["selected"] in tags else (tags[0] if tags else "")
    api_ok = False
    if running:
        try:
            now = api(settings, "GET", "/proxies/proxy", timeout=2).get("now", "")
            if now:
                current = now
            api_ok = True
        except Exception:
            api_ok = False
    has_config = os.path.exists(os.path.join(state_dir(), "config.json"))
    binary, binary_source = singbox_location()
    readiness = setup_status(settings, binary, running)
    if running:
        state = "connected" if api_ok else "error"
    elif readiness["state"] != "ready" and has_source:
        state = "missing"
    elif not has_source:
        state = "none"
    elif not has_config:
        state = "error"
    else:
        state = "disconnected"
    cur = next((s for s in servers if s.get("tag") == current), None)
    pings = read_json(os.path.join(state_dir(), "pings.json"), {})
    out = {
        "state": state, "running": running, "hasSource": has_source, "hasConfig": has_config,
        "singbox": readiness["binaryReady"], "setup": readiness, "installHint": INSTALL_HINT,
        "singboxSource": binary_source,
        "singboxPath": binary, "subscription": _active_sub_name(has_source),
        "proxy": f"127.0.0.1:{settings['proxyPort']}", "current": current,
        "currentServer": server_summary(cur) if cur else None,
        "count": len(servers), "updateHours": settings["updateHours"],
        "lastUpdate": {k: last.get(k) for k in ("time", "ok", "code", "message", "format", "servers",
                                                 "skippedCount", "info", "keptOld") if k in last},
        "delays": pings.get("delays", {}) if isinstance(pings, dict) else {},
        "pingTime": pings.get("time", 0) if isinstance(pings, dict) else 0,
        "mode": settings["mode"], "tunInstalled": tun_installed(), "tunState": tstate,
        "tunActive": tstate == "active", "checks": collect_checks() if settings["mode"] == "tun" or tstate else [],
    }
    if tstate in ("failed", "deactivating") or (tstate == "activating" and not running):
        state = out["state"] = "error"
        out["error"] = msg("stop_timeout") if tstate == "deactivating" else msg("service_failed", journal_tail(3) or tstate)
        return out
    if state == "error" and not running:
        out["error"] = last.get("message") or msg("no_config")
    elif state == "error":
        out["error"] = msg("api_failed", _log_tail(os.path.join(state_dir(), "sing-box.log")) or "-")
    elif state == "missing":
        out["error"] = readiness["error"] or (msg("sb_not_working", readiness["path"])
                        if readiness["state"] == "repair" else msg("no_singbox"))
    elif last and not last.get("ok"):
        out["warning"] = last.get("message", "")
    return out


def set_source(text):
    """Replaces the active subscription's link (creates the first one); the CLI's `vpn set`."""
    text = (text or "").strip()
    if not text:
        raise VpnError("empty")
    unwrap_source(text)                       # happ:// etc.: clear error before saving
    d = load_subs()
    if not d["active"]:
        sid = _new_sub_id(d)
        d["items"].append({"id": sid, "name": "", "created": time.time()})
        d["active"] = sid
    write_private(sub_link_file(d["active"]), text + "\n")
    save_subs(d)
    write_private(os.path.join(config_dir(), "source"), text + "\n")
    entry = update()
    _name_from_update(d["active"], entry)
    return entry


def _forget_state(tun_forget=True):
    marker = os.path.join(state_dir(), "tun_applied")
    if tun_forget and os.path.exists(marker) and tun_installed():
        try:
            _helper("forget", timeout=60)
        except VpnError:
            pass
    paths = [os.path.join(config_dir(), "source"), marker] + [
        os.path.join(state_dir(), f) for f in ("servers.json", "config.json", "probe.json", "pings.json",
                                               "last_update.json", "ipcheck.json")]
    for p in paths:
        try:
            os.unlink(p)
        except OSError:
            pass


def clear():
    """Forgets every saved subscription."""
    disconnect()
    _forget_state()
    shutil.rmtree(os.path.join(config_dir(), "subs"), ignore_errors=True)
    try:
        os.unlink(subs_file())
    except OSError:
        pass
    return status()


# ---- subscriptions -----------------------------------------------------------------------
# Only names and update results are in subscriptions.json; each link is in its own 600 file.
# The active link is also mirrored to `source`, which everything above reads.

SUB_ID = re.compile(r"[0-9a-f]{8}")


def subs_file():
    return os.path.join(config_dir(), "subscriptions.json")


def sub_link_file(sid):
    if not SUB_ID.fullmatch(sid or ""):
        raise VpnError("sub_unknown", sid)
    return os.path.join(config_dir(), "subs", sid)


def _clean_name(name):
    name = " ".join(str(name or "").split())
    return name if 0 < len(name) <= 60 and all(ch.isprintable() for ch in name) else ""


def _subs_raw():
    d = read_json(subs_file(), {})
    d = d if isinstance(d, dict) else {}
    items = []
    for it in d.get("items", []) if isinstance(d.get("items"), list) else []:
        if isinstance(it, dict) and SUB_ID.fullmatch(str(it.get("id", ""))) \
                and os.path.exists(os.path.join(config_dir(), "subs", it["id"])):
            items.append({"id": it["id"], "name": _clean_name(it.get("name")),
                          "created": float(it.get("created") or 0),
                          "lastUpdate": it.get("lastUpdate") if isinstance(it.get("lastUpdate"), dict) else {},
                          **({"kind": "file"} if it.get("kind") == "file" else {})})
    ids = [it["id"] for it in items]
    active = d.get("active") if d.get("active") in ids else (ids[0] if ids else "")
    return {"active": active, "items": items}


def _new_sub_id(d):
    while True:
        sid = secrets.token_hex(4)
        if sid not in [it["id"] for it in d["items"]]:
            return sid


def save_subs(d):
    write_private(subs_file(), json.dumps({"active": d["active"], "items": d["items"]}, indent=2, ensure_ascii=False))


def load_subs(migrate=True):
    """The saved subscriptions. A link saved before subscriptions existed becomes the first one."""
    d = _subs_raw()
    src = _source_text()
    if migrate and not d["items"] and src:
        sid = _new_sub_id(d)
        write_private(sub_link_file(sid), src + "\n")
        title = ((read_json(os.path.join(state_dir(), "last_update.json"), {}) or {}).get("info") or {}).get("title", "")
        d = {"active": sid, "items": [{"id": sid, "name": _clean_name(title), "created": time.time()}]}
        save_subs(d)
    return d


def _sub_hint(sid):
    """What the list may show about a link: the host of a URL or the number of pasted servers. Never the link."""
    try:
        link = unwrap_source(read_text(sub_link_file(sid)).strip())
    except VpnError:
        return {"kind": "app", "host": ""}
    if is_url(link):
        return {"kind": "url", "host": (urllib.parse.urlsplit(link).hostname or "")[:80]}
    return {"kind": "links", "count": sum(1 for line in link.splitlines() if "://" in line) or 1}


def _default_name(d, sid):
    hint = _sub_hint(sid)
    if hint.get("host"):
        return hint["host"]
    n = [it["id"] for it in d["items"]].index(sid) + 1 if sid in [it["id"] for it in d["items"]] else 1
    return ("Подписка " if lang_ru() else "Subscription ") + str(n)


def subs_list(migrate=True):
    d = load_subs(migrate)
    items = []
    for it in d["items"]:
        out = dict(it, **({} if it.get("kind") == "file" else _sub_hint(it["id"])))
        out["name"] = it["name"] or _default_name(d, it["id"])
        out["active"] = it["id"] == d["active"]
        items.append(out)
    return {"active": d["active"], "items": items}


def _record_sub_update(entry):
    d = _subs_raw()
    if not d["active"]:
        return
    for it in d["items"]:
        if it["id"] == d["active"]:
            it["lastUpdate"] = {k: entry.get(k) for k in ("time", "ok", "servers", "message", "keptOld") if k in entry}
            title = (entry.get("info") or {}).get("title")
            if title:
                it["lastUpdate"]["title"] = str(title)[:80]
    save_subs(d)


def _name_from_update(sid, entry):
    d = _subs_raw()
    for it in d["items"]:
        if it["id"] == sid and not it["name"]:
            it["name"] = _clean_name((entry.get("info") or {}).get("title", ""))
            save_subs(d)


def _switch_with_rollback(d, sid, prepared=None):
    """Makes sid active and updates; on failure the previous active link, its result and config stay."""
    prev_active = d["active"]
    prev_source = read_text(os.path.join(config_dir(), "source"))
    last_path = os.path.join(state_dir(), "last_update.json")
    prev_last = read_text(last_path) if os.path.exists(last_path) else None
    d["active"] = sid
    save_subs(d)
    write_private(os.path.join(config_dir(), "source"), read_text(sub_link_file(sid)))
    try:
        return update(prepared=prepared, restart=prepared is None)
    except VpnError:
        d2 = _subs_raw()
        d2["active"] = prev_active if prev_active in [it["id"] for it in d2["items"]] else d2["active"]
        save_subs(d2)
        if prev_source.strip():
            write_private(os.path.join(config_dir(), "source"), prev_source)
        else:
            try:
                os.unlink(os.path.join(config_dir(), "source"))
            except OSError:
                pass
        if prev_last is not None:
            write_private(last_path, prev_last)
        else:
            try:
                os.unlink(last_path)
            except OSError:
                pass
        raise


def sub_add(text, name="", prepared=None, local_file=False):
    text = (text or "").strip()
    if not text:
        raise VpnError("empty")
    unwrap_source(text)                       # happ:// etc.: clear error before saving anything
    name = _clean_name(name)
    d = load_subs()
    sid = _new_sub_id(d)
    write_private(sub_link_file(sid), text + "\n")
    d["items"].append({"id": sid, "name": name, "created": time.time()})
    if local_file:
        d["items"][-1]["kind"] = "file"
    try:
        entry = _switch_with_rollback(d, sid, prepared)
    except VpnError:
        d2 = _subs_raw()
        d2["items"] = [it for it in d2["items"] if it["id"] != sid]
        save_subs(d2)
        try:
            os.unlink(sub_link_file(sid))
        except OSError:
            pass
        raise
    if not name:
        _name_from_update(sid, entry)
    return dict(subs_list(), ok=True, added=sid, servers=entry.get("servers", 0),
                skippedCount=entry.get("skippedCount", 0))


def _find_sub(d, sid):
    if sid not in [it["id"] for it in d["items"]]:
        raise VpnError("sub_unknown", sid)


def sub_use(sid):
    d = load_subs()
    _find_sub(d, sid)
    entry = update() if sid == d["active"] else _switch_with_rollback(d, sid)
    return dict(subs_list(), ok=True, servers=entry.get("servers", 0))


def sub_rename(sid, name):
    d = load_subs()
    _find_sub(d, sid)
    clean = _clean_name(name)
    if not clean:
        raise VpnError("sub_bad_name")
    for it in d["items"]:
        if it["id"] == sid:
            it["name"] = clean
    save_subs(d)
    return dict(subs_list(), ok=True)


def sub_remove(sid):
    d = load_subs()
    _find_sub(d, sid)
    was_active = d["active"] == sid
    d["items"] = [it for it in d["items"] if it["id"] != sid]
    try:
        os.unlink(sub_link_file(sid))
    except OSError:
        pass
    out = {}
    if was_active:
        disconnect()
        _forget_state(tun_forget=not d["items"])
        d["active"] = d["items"][0]["id"] if d["items"] else ""
        save_subs(d)
        if d["active"]:
            write_private(os.path.join(config_dir(), "source"), read_text(sub_link_file(d["active"])))
            try:
                update()
            except VpnError as e:
                out["updateError"] = e.as_dict()["message"]
    else:
        save_subs(d)
    return dict(subs_list(), ok=True, **out)


# ---- external IP through the VPN ---------------------------------------------------------

IP_SERVICES = ("https://ipinfo.io/json", "https://api.ipify.org?format=json")


def ipcheck():
    """{ip, country, ...} as seen by an outside service through our own VPN. Never runs when not connected."""
    settings = load_settings_readonly()
    if tun_state() == "active":
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))       # routed into serp-tun0
        via = "tun"
    elif is_running():
        proxy = f"http://127.0.0.1:{settings['proxyPort']}"
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({"http": proxy, "https": proxy}))
        via = "proxy"
    else:
        raise VpnError("not_connected")
    services = [u for u in os.environ.get("SERP_VPN_IP_SERVICES", "").split(",") if u] or list(IP_SERVICES)
    last = "-"
    for url in services:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "curl/8.0", "Accept": "application/json"})
            with opener.open(req, timeout=12) as r:
                data = json.loads(r.read(64 * 1024).decode("utf-8", errors="replace"))
            ip = str(data.get("ip", "")).strip()
            ipaddress.ip_address(ip)
            cc = str(data.get("country", "") or "").strip().upper()
            cc = cc if re.fullmatch(r"[A-Z]{2}", cc) else ""
            out = {"ok": True, "ip": ip, "country": cc, "countryName": country_name(cc) if cc else "",
                   "flag": flag(cc) if cc else "", "time": time.time(), "via": via,
                   "service": urllib.parse.urlsplit(url).hostname or "", "server": status_current(settings)}
            write_private(os.path.join(state_dir(), "ipcheck.json"), json.dumps(out, ensure_ascii=False))
            return out
        except urllib.error.HTTPError as e:
            last = f"HTTP {e.code}"
        except (urllib.error.URLError, OSError, ValueError) as e:
            reason = getattr(e, "reason", None)
            last = reason if isinstance(reason, str) else type(reason or e).__name__
    raise VpnError("ip_failed", last)


def _active_sub_name(has_source):
    """Read-only (status never creates files): name of the active subscription."""
    if not has_source:
        return ""
    d = _subs_raw()
    for it in d["items"]:
        if it["id"] == d["active"]:
            return it["name"] or _default_name(d, it["id"])
    return ""


def status_current(settings):
    tags = [s.get("tag") for s in _servers()]
    return settings["selected"] if settings["selected"] in tags else (tags[0] if tags else "")


# ---- sing-box: info, install, choose ------------------------------------------------------


def singbox_info():
    sb = _singbox_module()
    path, source = singbox_location()
    checked = sb.probe(path) if path else {"ok": False, "version": "", "error": "not_found"}
    found = []
    for p in sb.candidates():
        found.append({"path": p, "system": sb.system_path(p)})
    return {"ok": True, "path": path, "source": source, "version": checked["version"], "works": checked["ok"],
            "error": checked["error"] if path else "", "managedPath": sb.managed_path(), "arch": sb.arch_name(),
            "tunUsable": sb.system_path(path), "candidates": found, "installHint": INSTALL_HINT}


def _emit(event):
    print(json.dumps(event, ensure_ascii=False), flush=True)


def singbox_install(as_json):
    sb = _singbox_module()
    emit = _emit if as_json else (lambda e: None)
    if vpn_running():
        raise VpnError("setup_connected")
    try:
        res = sb.install(emit)
    except sb.SingboxError as e:
        raise VpnError(e.code, e.detail)
    except OSError as e:
        raise VpnError("setup_storage", e.strerror or type(e).__name__) from None
    settings = load_settings()
    settings["singboxPath"] = res["path"]
    save_settings(settings)
    return res


PACKAGE_HELPER = "/usr/libexec/serpantinum/serp-vpn-packages"
SYSTEM_SINGBOX = ("/usr/bin/sing-box", "/usr/local/bin/sing-box")
TUN_DEVICE = "/dev/net/tun"
TUN_TOOLS = {"iproute": ("/usr/sbin/ip", "/usr/bin/ip"), "nftables": ("/usr/sbin/nft", "/usr/bin/nft")}


def system_singbox():
    # Same precedence as the root helper.
    return next((p for p in SYSTEM_SINGBOX if _executable(p)), "")


def setup_status(settings, binary, running=False):
    sb = _singbox_module()
    tun = settings["mode"] == "tun"
    path = system_singbox() if tun else binary
    checked = sb.probe(path, timeout=2) if path and not running else {}
    version = re.match(r"^(\d+)\.(\d+)\.", checked.get("version", ""))
    binary_ready = running or (checked.get("ok", False) and
                               (not tun or (version is not None and tuple(map(int, version.groups())) >= (1, 12))))
    exists = bool(path) or any(os.path.lexists(p) for p in (SYSTEM_SINGBOX if tun else
                                                           (managed_singbox(), settings["singboxPath"])))
    can_install = (_executable(PACKAGE_HELPER) and _executable("/usr/bin/dnf5") and
                   bool(_tool("SERP_VPN_PKEXEC", "pkexec")))
    deps = []
    error = ""
    if tun and not running:
        if not tun_installed() or not _tool("SERP_VPN_PKEXEC", "pkexec"):
            error = msg("tun_not_installed")
        elif not os.path.exists(TUN_DEVICE):
            error = msg("setup_tun")
        deps = [pkg for pkg, paths in TUN_TOOLS.items() if not any(_executable(p) for p in paths)]
    return {"state": "blocked" if error else "ready" if binary_ready and not deps else
            "repair" if exists and not binary_ready else "missing",
            "error": error, "path": path, "binaryReady": binary_ready, "systemInstall": can_install,
            "packages": deps, "version": checked.get("version", ""), "arch": sb.arch_name(),
            "pipewire": bool(shutil.which("pipewire")),
            "yaml": importlib.util.find_spec("yaml") is not None}


def install_fedora_packages(packages, emit, action="install"):
    pkexec = _tool("SERP_VPN_PKEXEC", "pkexec")
    if not pkexec or not _executable(PACKAGE_HELPER) or not _executable("/usr/bin/dnf5"):
        raise VpnError("setup_admin")
    emit({"event": "stage", "stage": "packages", "packages": packages})
    # No timeout or cancellation across an RPM transaction. DNF handles download retries.
    rc, out, _ = _run([pkexec, "--disable-internal-agent", PACKAGE_HELPER,
                       action, *packages], timeout=None)
    try:
        result = json.loads(out.strip().splitlines()[-1])
    except (ValueError, IndexError):
        result = {}
    if rc in (126, 127) and not result:
        raise VpnError("setup_auth")
    if rc or result.get("ok") is not True:
        raise VpnError("setup_packages", _strip_ansi(result.get("detail") or f"DNF5 ({rc})"))


def read_setup_file(path):
    try:
        if path.startswith("file:"):
            url = urllib.parse.urlsplit(path)
            if url.netloc or url.query or url.fragment:
                raise ValueError("local file required")
            path = urllib.request.url2pathname(url.path)
        if not os.path.isfile(path):
            raise ValueError("not a regular file")
        with open(path, "rb") as f:
            raw = f.read(5 * 1024 * 1024 + 1)
        if len(raw) > 5 * 1024 * 1024:
            raise VpnError("too_large")
        text = raw.decode("utf-8-sig").strip()
        if is_url(unwrap_source(text)):
            raise ValueError("a configuration file must contain the profile")
        return text
    except (OSError, ValueError) as e:
        raise VpnError("setup_file", type(e).__name__) from None


def check_setup_config(cfg, settings, binary):
    """Check without touching the running network or echoing provider data."""
    if settings["mode"] == "tun":
        rc, out, _ = _run([helper_path(), "check-input"], json.dumps(tun_payload(cfg, settings)), timeout=15)
        try:
            checked = json.loads(out)["config"] if rc == 0 else None
        except (ValueError, KeyError):
            checked = None
        if not checked or not singbox_check(checked, binary)[0]:
            raise VpnError("check_failed", "TUN / sing-box check")
    if not singbox_check(cfg, binary)[0]:
        raise VpnError("check_failed", "sing-box check")


def vpn_setup(source, name, emit, *, file_path="", system=False, allow_yaml=False):
    emit({"event": "stage", "stage": "system"})
    if vpn_running() or tun_state() in ("activating", "deactivating"):
        raise VpnError("setup_connected")
    settings = load_settings_readonly()
    tun = settings["mode"] == "tun"
    health = setup_status(settings, singbox_bin())
    if health["error"]:
        raise VpnError("tun_not_installed" if not tun_installed() or
                       not _tool("SERP_VPN_PKEXEC", "pkexec") else "setup_tun")
    emit({"event": "stage", "stage": "binary"})
    binary = health["path"] if health["binaryReady"] else ""
    sb = _singbox_module()
    if not binary and not tun:
        binary = next((p for p in sb.candidates() if p != health["path"] and sb.probe(p, timeout=2)["ok"]), "")
    if not binary and not (tun or system) and not health["arch"]:
        raise VpnError("sb_arch", os.uname().machine if hasattr(os, "uname") else "?")

    new_source = bool(file_path or source.strip())
    source = read_setup_file(file_path) if file_path else source.strip() or _source_text()
    prepared = None
    if source:
        emit({"event": "stage", "stage": "profile"})
        try:
            text, info = (source, {}) if file_path else load_source_text(source, settings)
        except ValueError:
            raise VpnError("fetch_failed", "URL") from None
        try:
            parsed = parse_subscription(text)
        except VpnError as e:
            if e.code == "no_servers":
                # Parser errors can contain values supplied by the provider.
                raise VpnError(e.code, "") from None
            if e.code != "need_yaml" or not allow_yaml:
                raise
            install_fedora_packages(["python3-pyyaml"], emit)
            importlib.invalidate_caches()
            parsed = parse_subscription(text)
        cfg = build_config(parsed["servers"], settings)
        prepared = parsed, info, cfg
    elif file_path:
        raise VpnError("empty")

    def validate(binary_to_check):
        emit({"event": "stage", "stage": "config"})
        check_setup_config(cfg, settings, binary_to_check)

    archive = False
    if not binary:
        if tun or system:
            rpm_installed = _run(["/usr/bin/rpm", "-q", "sing-box"], timeout=5)[0] == 0
            action = "upgrade" if rpm_installed and health["version"] else "repair" if rpm_installed else "install"
            install_fedora_packages(["sing-box"], emit, action=action)
            binary = system_singbox()
        else:
            archive = True
            binary = sb.install(emit, validate=validate if prepared else None)["path"]
    if health["packages"]:
        install_fedora_packages(health["packages"], emit)
    if not archive:
        emit({"event": "stage", "stage": "test"})
    health = setup_status(settings, binary)
    if not health["binaryReady"] or health["packages"] or health["error"]:
        raise VpnError("sb_not_working", health["error"] or ", ".join(health["packages"]) or "version")

    if prepared and not archive:
        validate(binary)

    result = {"ok": True, "path": binary, "version": health["version"], "setupComplete": True}
    choose_binary = not tun and binary != singbox_bin()
    saved_settings = _merge_settings(read_json(os.path.join(config_dir(), "settings.json"), {}))
    if choose_binary or (prepared and not saved_settings["secret"]):
        if choose_binary:
            settings["singboxPath"] = binary
        save_settings(settings)
    if prepared:
        result.update(sub_add(source, name, prepared, local_file=bool(file_path)) if new_source else
                      update(prepared=prepared, restart=False))
    return result


def singbox_use(path):
    path = (path or "").strip()
    settings = load_settings()
    if path:
        sb = _singbox_module()
        path = os.path.realpath(os.path.expanduser(path))
        checked = sb.probe(path)
        if not checked["ok"]:
            raise VpnError("sb_bad_path", checked["error"])
    settings["singboxPath"] = path
    save_settings(settings)
    return singbox_info()


def test(text):
    """Dry run: download, parse, list, check. Writes nothing to the config/state directories, starts nothing."""
    settings = load_settings_readonly()
    raw, info = load_source_text(text, settings)
    parsed = parse_subscription(raw)
    out = {"ok": False, "format": parsed["format"], "servers": [server_summary(s) for s in parsed["servers"]],
           "skipped": parsed["errors"], "info": info}
    cfg = build_config(parsed["servers"], settings)
    try:
        ok, detail = singbox_check(cfg)
        out.update(check="ok" if ok else "failed", checkDetail=detail, ok=ok, singbox=singbox_version())
    except VpnError as e:
        out.update(check="no_singbox", checkDetail=e.as_dict()["message"])
    return out


# ---- CLI -------------------------------------------------------------------------------

STATE_NAMES = {"connected": ("Connected", "Подключено"), "disconnected": ("Disconnected", "Отключено"),
               "none": ("No subscription", "Нет подписки"), "missing": ("sing-box is not installed", "sing-box не установлен"),
               "error": ("Error", "Ошибка")}


def _print_human(cmd, data):
    ru = lang_ru()
    L = (lambda en, r: r if ru else en)
    if cmd == "test":
        print(L("Format: ", "Формат: ") + data.get("format", ""))
        if (data.get("info") or {}).get("title"):
            print(L("Title: ", "Название: ") + data["info"]["title"])
        servers = data.get("servers", [])
        print(L("Servers: ", "Серверов: ") + str(len(servers)))
        for i, s in enumerate(servers, 1):
            c = (s["flag"] + " " + s["countryName"]) if s["country"] else "?"
            print(f"  {i:3d}. {s['name'][:44]:44s} {s['protocol']:11s} {s['address']}:{s['port']}  {c}")
        if data.get("skipped"):
            print(L("Skipped: ", "Пропущено: ") + str(len(data["skipped"])))
            for e in data["skipped"][:30]:
                label = f" ({e['name']})" if e.get("name") else ""
                print(f"     #{e['item']}{label}: {e['error']}")
        check = data.get("check")
        if check == "ok":
            print("sing-box check: OK" + (f" (sing-box {data['singbox']})" if data.get("singbox") else ""))
        elif check == "failed":
            print("sing-box check: " + L("FAILED", "ОШИБКА") + "\n  " + data.get("checkDetail", ""))
        else:
            print("sing-box check: " + L("not run: ", "не выполнен: ") + data.get("checkDetail", ""))
        print(L("Nothing was saved or started.", "Ничего не сохранено и не запущено."))
    elif cmd == "list":
        for s in data.get("servers", []):
            print(f"{s['flag'] or '  '} {s['name'][:44]:44s} {s['protocol']:11s} {s['address']}:{s['port']}")
    elif cmd in ("update", "set-source"):
        if data.get("skipped") in ("fresh", "no_source"):
            print(L("No update needed.", "Обновление не нужно."))
        else:
            skipped = data.get("skippedCount", 0)
            print(L(f"Subscription updated: {data.get('servers', 0)} servers", f"Подписка обновлена: серверов {data.get('servers', 0)}")
                  + (L(f", {skipped} skipped", f", пропущено {skipped}") if skipped else ""))
            if data.get("restartError"):
                print(data["restartError"])
    elif cmd == "check":
        print(L("TUN service: ", "Служба TUN: ") + (data.get("tunState") or "-") if data.get("tunInstalled")
              else L("TUN service: not installed", "Служба TUN: не установлена"))
        for c in data.get("checks", []):
            print(("! " if c["level"] == "warn" else "i ") + c["message"])
        if not data.get("checks"):
            print(L("No conflicts found.", "Конфликтов не найдено."))
    elif cmd == "ping":
        for tag, d in sorted(data.get("delays", {}).items(), key=lambda kv: (kv[1] <= 0, kv[1])):
            print(f"{(str(d) + ' ms') if d > 0 else '-':>8}  {tag}")
    elif cmd in ("subs", "sub-add", "sub-use", "sub-rename", "sub-remove"):
        for it in data.get("items", []):
            where = it.get("host") or (str(it.get("count", "")) + L(" links", " ссылок") if it.get("kind") == "links" else "")
            lu = it.get("lastUpdate") or {}
            when = time.strftime("%Y-%m-%d %H:%M", time.localtime(lu["time"])) if lu.get("time") else "-"
            print(f"{'*' if it.get('active') else ' '} {it['id']}  {it['name'][:30]:30s} {where[:30]:30s} {when}"
                  + ("" if lu.get("ok", True) else "  !"))
        if data.get("updateError"):
            print(data["updateError"])
    elif cmd == "ipcheck":
        print(f"{data.get('ip', '')}  {data.get('flag', '')} {data.get('countryName', '')}".rstrip())
    elif cmd in ("singbox-info", "singbox-use", "singbox-install"):
        if cmd == "singbox-install":
            print(L("Installed: ", "Установлено: ") + data.get("path", "") + "  (sing-box " + data.get("version", "") + ")")
            print("SHA-256: " + data.get("sha256", "") + ("" if data.get("verified")
                  else L("  (GitHub published no checksum for it)", "  (GitHub не опубликовал контрольную сумму)")))
        else:
            print("sing-box: " + (data.get("path") or L("not found", "не найден"))
                  + (f"  ({data.get('version')})" if data.get("version") else "")
                  + (f"  [{data.get('source')}]" if data.get("source") else ""))
            for c in data.get("candidates", []):
                print("  " + c["path"] + ("  (TUN ok)" if c["system"] else ""))
    else:
        st = data.get("state", "")
        print(L("State: ", "Состояние: ") + STATE_NAMES.get(st, (st, st))[1 if ru else 0])
        cur = data.get("currentServer")
        if cur:
            print(L("Server: ", "Сервер: ") + f"{cur['flag']} {cur['name']} ({cur['protocol']})".strip())
        print(L("Servers: ", "Серверов: ") + str(data.get("count", 0)))
        print(L("Mode: ", "Режим: ") + (L("TUN (whole system)", "TUN (вся система)") if data.get("mode") == "tun"
                                         else L("proxy", "прокси"))
              + ("" if data.get("tunInstalled") else L(" (TUN not installed)", " (TUN не установлен)")))
        if data.get("forced"):
            print(L("Force off: ", "Принудительное выключение: ")
                  + ", ".join(f"{k} {v}" for k, v in data["forced"].items()))
        for c in data.get("checks", []):
            print(("! " if c["level"] == "warn" else "i ") + c["message"])
        if data.get("running"):
            print(L("Proxy (HTTP and SOCKS5): ", "Прокси (HTTP и SOCKS5): ") + data.get("proxy", ""))
        lu = data.get("lastUpdate") or {}
        if lu.get("time"):
            print(L("Updated: ", "Обновлено: ") + time.strftime("%Y-%m-%d %H:%M", time.localtime(lu["time"]))
                  + ("" if lu.get("ok") else "  (" + str(lu.get("message", "")) + ")"))
        if data.get("error"):
            print(L("Error: ", "Ошибка: ") + data["error"])


def main(argv):
    if hasattr(signal, "SIGTERM"):           # the shell stops a ping when the panel closes:
        signal.signal(signal.SIGTERM, lambda *a: sys.exit(143))   # run `finally`, stop the probe
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    if not args or args[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    cmd, rest = args[0], args[1:]
    try:
        if cmd == "test":
            data = test(rest[0] if rest and rest[0] != "-" else sys.stdin.read())
        elif cmd == "set-source":
            data = set_source(sys.stdin.read())
        elif cmd == "update":
            data = update(auto="--auto" in rest)
        elif cmd == "list":
            data = {"servers": [server_summary(s) for s in _servers()]}
        elif cmd == "status":
            data = status()
        elif cmd == "connect":
            data = connect()
        elif cmd == "disconnect":
            data = disconnect()
        elif cmd == "select":
            data = select(rest[0] if rest else "")
        elif cmd == "ping":
            data = ping()
        elif cmd == "clear":
            data = clear()
        elif cmd == "mode":
            data = set_mode(rest[0] if rest else "")
        elif cmd == "check":
            data = {"checks": collect_checks(), "tunInstalled": tun_installed(), "tunState": tun_state()}
        elif cmd == "force-off":
            data = force_off()
        elif cmd == "ipcheck":
            data = ipcheck()
        elif cmd == "subs":
            data = subs_list()
        elif cmd == "sub-add":
            name = next((a[7:] for a in rest if a.startswith("--name=")), "")
            data = sub_add(sys.stdin.read(), name)
        elif cmd == "sub-use":
            data = sub_use(rest[0] if rest else "")
        elif cmd == "sub-rename":
            data = sub_rename(rest[0] if rest else "", " ".join(rest[1:]))
        elif cmd == "sub-remove":
            data = sub_remove(rest[0] if rest else "")
        elif cmd == "singbox-info":
            data = singbox_info()
        elif cmd == "singbox-install":
            data = singbox_install(as_json)
        elif cmd == "setup":
            name = next((a[7:] for a in rest if a.startswith("--name=")), "")
            file_path = next((a[7:] for a in rest if a.startswith("--file=")), "")
            try:
                data = vpn_setup(sys.stdin.read(), name, _emit if as_json else (lambda _: None),
                                 file_path=file_path, system="--system" in rest, allow_yaml="--yaml" in rest)
            except _singbox_module().SingboxError as e:
                raise VpnError(e.code, e.detail) from None
            except OSError as e:
                raise VpnError("setup_storage", e.strerror or type(e).__name__) from None
        elif cmd == "singbox-use":
            data = singbox_use(rest[0] if rest else "")
        else:
            print(f"unknown command: {cmd}", file=sys.stderr)
            return 64
    except VpnError as e:
        err = e.as_dict()
        if as_json:
            print(json.dumps({"ok": False, "error": err}, ensure_ascii=False))
        else:
            print(err["message"], file=sys.stderr)
        return 2 if e.code == "no_singbox" else 1
    except KeyboardInterrupt:
        return 130
    if as_json:
        if "ok" not in data:
            data = dict(data, ok=True)
        print(json.dumps(data, ensure_ascii=False))
    else:
        _print_human(cmd, data)
    if cmd == "test" and data.get("check") == "failed":
        return 1
    if cmd == "test" and data.get("check") == "no_singbox":
        return 2                              # parsed fine, but the check could not run
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
