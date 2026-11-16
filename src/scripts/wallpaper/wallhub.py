#!/usr/bin/env python3
"""Search Wallpapers backend for Serpantinum (Settings -> Search Wallpapers).

Real internet search through official, documented APIs only:
  * Wallhaven      https://wallhaven.cc/help/api            (no key needed for SFW)
  * Wikimedia Commons MediaWiki API                         (no key)
  * Openverse      https://api.openverse.org/v1/            (no key, rate limited)
  * Pexels         https://www.pexels.com/api/              (user API key)
  * Pixabay        https://pixabay.com/api/docs/            (user API key)
  * Giphy          https://developers.giphy.com/            (user API key)
  * Brave Search   https://brave.com/search/api/            (user API key)
  * Sepia Search   https://sepiasearch.org/                 (public PeerTube index)

Optional query translation (ru -> en) uses the public MyMemory API and is
reported back so the UI can show what was actually sent. Nothing here executes
downloaded content: files are streamed to disk, size-capped, identified by
their magic bytes, decoded with ffprobe and stored mode 0644.

Every command prints exactly one JSON object on stdout as its last line
(download also prints "P <done> <total>" progress lines before it).
"""
import argparse
import concurrent.futures
import contextlib
import datetime
import hashlib
import http.client
import io
import ipaddress
import json
import os
import re
import shutil
import signal
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

VERSION = "2.0"
UA = "SerpantinumSearchWallpapers/" + VERSION + " (+https://github.com/ilyamiro/serpantinum; desktop wallpaper search client)"
HOME = os.path.expanduser("~")
CONFIG_DIR = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
STATE_DIR = os.environ.get("QS_STATE_DIR") or os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local/state"), "serpantinum")
CACHE_DIR = os.environ.get("QS_CACHE_DIR") or os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"), "serpantinum")
# API keys live outside settings.json, which Themess can export and share.
SECRETS_FILE = os.path.join(CONFIG_DIR, "serpantinum", "secrets", "wallpaper_hub.json")
HUB_STATE = os.path.join(STATE_DIR, "wallpaper_hub")
LIBRARY_FILE = os.path.join(HUB_STATE, "library.json")
FAVORITES_FILE = os.path.join(HUB_STATE, "favorites.json")
SOURCES_FILE = os.path.join(HUB_STATE, "sources.json")
QUALITY_CACHE = os.path.join(HUB_STATE, "quality.json")
THUMB_DIR = os.path.join(CACHE_DIR, "wallpaper_hub", "thumbs")
# Search history stays on this machine (mode 600), never in settings.json/Themess.
HISTORY_FILE = os.path.join(HUB_STATE, "history.json")
HISTORY_MAX = 25

TIMEOUT = 12
PER_PAGE = 24
KEY_SOURCES = ("pexels", "pixabay", "giphy", "wallhaven", "brave", "steam")
RES = {"any": (0, 0), "1080p": (1920, 1080), "1440p": (2560, 1440), "4k": (3840, 2160), "8k": (7680, 4320)}
MEDIA_EXT = {"jpg", "png", "webp", "gif", "apng", "mp4", "webm"}
ANIMATION_FORMATS = {"gif", "webp", "apng"}


class SourceError(Exception):
    pass


class Offline(Exception):
    pass


def emit(obj):
    # ensure_ascii keeps every line pure ASCII: a console or pipe with a legacy
    # encoding can never turn a title with an unusual character into a crash.
    sys.stdout.write(json.dumps(obj, ensure_ascii=True) + "\n")
    sys.stdout.flush()


def ensure_private_dir(path):
    os.makedirs(path, exist_ok=True)
    try:
        os.chmod(path, 0o700)
    except OSError:
        pass


def read_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json_atomic(path, data, mode=0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=1)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


@contextlib.contextmanager
def state_lock(path):
    ensure_private_dir(os.path.dirname(path))
    with open(path + ".lock", "a+b") as lock:
        if os.name == "nt":
            import msvcrt
            lock.seek(0)
            msvcrt.locking(lock.fileno(), msvcrt.LK_LOCK, 1)
        else:
            import fcntl
            fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def load_keys():
    data = read_json(SECRETS_FILE, {})
    if not isinstance(data, dict):
        return {}
    return {k: str(v) for k, v in data.items() if k in KEY_SOURCES and v}


# --------------------------------------------------------------------------- HTTP

class Transient(Exception):
    """A dropped connection or TLS hiccup: worth exactly one quiet retry."""


def classify_net_error(reason, timeout):
    """Maps a low-level network error to SourceError / Offline / Transient.
    ssl.SSLError is an OSError subclass, so it must be tested before OSError:
    a TLS problem with one site does not mean the computer is offline."""
    if isinstance(reason, (socket.timeout, TimeoutError)):
        return SourceError("timed out after %ds" % timeout)
    if isinstance(reason, ssl.SSLCertVerificationError):
        return SourceError("secure connection refused: " + str(getattr(reason, "verify_message", "") or reason))
    if isinstance(reason, (ssl.SSLError, ConnectionResetError, ConnectionAbortedError, http.client.RemoteDisconnected,
                           http.client.IncompleteRead)):
        return Transient("connection dropped (%s)" % reason)
    if isinstance(reason, (socket.gaierror, ConnectionRefusedError, OSError)):
        return Offline(str(reason))
    return SourceError(str(reason))


def http_get(url, headers=None, timeout=TIMEOUT, want_json=True, retries=1):
    for attempt in range(retries + 1):
        try:
            return _http_get_once(url, headers, timeout, want_json)
        except Transient as e:
            if attempt >= retries:
                raise SourceError(str(e))
            time.sleep(0.5)


def _http_get_once(url, headers, timeout, want_json):
    h = {"User-Agent": UA, "Accept": "application/json" if want_json else "*/*"}
    req = urllib.request.Request(url, headers=h)
    # API credentials belong to the original request, including on redirects.
    for name, value in (headers or {}).items():
        req.add_unredirected_header(name, value)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read(8 * 1024 * 1024)
    except urllib.error.HTTPError as e:
        detail = ""
        try:
            detail = e.read(2000).decode("utf-8", "replace").strip()
        except Exception:
            pass
        detail = re.sub(r"<[^>]+>", " ", detail)
        detail = re.sub(r"\s+", " ", detail)[:240]
        if e.code == 429:
            raise SourceError("rate limit reached (HTTP 429); try again in a minute")
        secret_values = list((headers or {}).values()) if headers else []
        params = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)
        secret_values.extend(value for name in ("key", "api_key", "apikey") for value in params.get(name, []))
        for secret in secret_values:
            if secret:
                detail = detail.replace(secret, "[redacted]")
        if e.code in (401, 403) and secret_values:
            raise SourceError("HTTP %d: API key rejected or access denied for this plan" % e.code)
        raise SourceError("HTTP %d %s%s" % (e.code, e.reason or "", (": " + detail) if detail else ""))
    except urllib.error.URLError as e:
        raise classify_net_error(e.reason, timeout)
    except (socket.timeout, TimeoutError, ssl.SSLError, ConnectionError, http.client.HTTPException) as e:
        raise classify_net_error(e, timeout)
    if not want_json:
        return body
    try:
        return json.loads(body.decode("utf-8"))
    except ValueError:
        raise SourceError("source returned a non-JSON answer")


def has_cyrillic(s):
    return bool(re.search(r"[Ѐ-ӿ]", s or ""))


def translate(text):
    """ru -> en through MyMemory. Returns (translation or None, error or None)."""
    url = "https://api.mymemory.translated.net/get?" + urllib.parse.urlencode({"q": text, "langpair": "ru|en"})
    try:
        d = http_get(url, timeout=8)
    except (SourceError, Offline) as e:
        return None, str(e)
    if int(d.get("responseStatus") or 0) != 200:
        return None, str(d.get("responseDetails") or "translation refused")
    out = ((d.get("responseData") or {}).get("translatedText") or "").strip()
    if not out or out.upper().startswith("MYMEMORY WARNING"):
        return None, out or "empty translation"
    return out, None


# --------------------------------------------------------------------------- normalisation

def ext_from(mime="", url=""):
    m = (mime or "").split(";", 1)[0].strip().lower()
    table = {"image/jpeg": "jpg", "image/jpg": "jpg", "image/png": "png", "image/webp": "webp",
             "image/gif": "gif", "image/apng": "apng", "video/mp4": "mp4", "video/webm": "webm",
             "audio/webm": "webm"}
    if m == "image/png" and urllib.parse.urlsplit(url or "").path.lower().endswith(".apng"):
        return "apng"
    if m in table:
        return table[m]
    path = urllib.parse.urlparse(url or "").path.lower()
    e = path.rsplit(".", 1)[-1] if "." in path else ""
    e = "jpg" if e == "jpeg" else e
    return e if e in MEDIA_EXT else ""


def kind_of(fmt):
    if fmt in ("mp4", "webm"):
        return "video"
    if fmt in ("gif", "apng"):
        return "animated"
    return "image"


def item(**kw):
    base = {
        "id": "", "source": "", "sourceName": "", "title": "", "pageUrl": "", "thumb": "", "preview": "",
        "url": "", "previewVideo": "", "created": "", "thumbHelper": False, "width": 0, "height": 0, "format": "", "kind": "", "size": 0, "fps": 0,
        "duration": 0, "codec": "", "bitrate": 0, "author": "", "license": "", "sourceLink": "",
        "provenance": "unknown", "provenanceReason": "", "notes": [], "originalAvailable": True, "external": False,
        "previewAnimation": "", "animationFrames": 0,
    }
    base.update(kw)
    if not base["kind"]:
        base["kind"] = kind_of(base["format"])
    if base["kind"] == "video" and base["duration"] and base["size"] and not base["bitrate"]:
        base["bitrate"] = int(base["size"] * 8 / base["duration"])
        base["bitrateEstimated"] = True
    base["qualityKnown"] = bool(base["width"] and base["height"] and base["size"])
    return base


def strip_html(s):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", s or "")).strip()


# --------------------------------------------------------------------------- sources
#
# What every source really offers. The search planner reads this table, so a
# filter a source cannot honour skips that source with a stated reason instead
# of silently returning wrong results:
#   kinds - media kinds the source hosts (image / animated / video)
#   sorts - orders the source itself can produce; "resolution" is done locally
#   safe  - "filter": the source has a content filter we switch on
#           "policy": the source does not allow explicit content at all
#           "none":   no content filter (skipped while Safe Search is on)
#   key   - "none" | "optional" | "required" (the user's own free key)
CAPS = {
    "brave": {"name": "Brave Search", "kinds": ["image", "animated", "video"], "sorts": ["relevance", "resolution"],
              "safe": "filter", "key": "required", "formats": ["jpg", "png", "webp", "gif", "mp4", "webm"],
              "nativeRu": True, "limits": "per plan; images one batch, videos up to 10 pages",
              "keyUrl": "https://api-dashboard.search.brave.com/"},
    "sepia": {"name": "Sepia Search / PeerTube", "kinds": ["video"], "sorts": ["relevance", "resolution"],
              "safe": "filter", "key": "none", "formats": [], "nativeRu": True,
              "limits": "public PeerTube videos; coverage depends on the index", "keyUrl": ""},
    "local": {"name": "My Wallpapers", "kinds": ["image", "animated", "video"], "sorts": ["relevance", "resolution", "newest"],
              "safe": "local", "key": "none", "formats": sorted(MEDIA_EXT), "nativeRu": True,
              "limits": "personal library and selected folders", "keyUrl": ""},
    "links": {"name": "Custom URLs / Feeds", "kinds": ["image", "animated", "video"], "sorts": ["relevance", "resolution"],
              "safe": "none", "key": "none", "formats": sorted(MEDIA_EXT), "nativeRu": True,
              "limits": "direct files, RSS/Atom enclosures and JSON Feed attachments", "keyUrl": ""},
    "steam": {"name": "Steam Workshop", "kinds": ["video"], "sorts": ["relevance", "resolution", "newest"],
              "safe": "none", "key": "required", "formats": [], "nativeRu": True,
              "limits": "Workshop video pages only; use My Wallpapers for local Steam files", "keyUrl": "https://steamcommunity.com/dev/apikey"},
    "wallhaven": {"name": "Wallhaven", "kinds": ["image"], "sorts": ["relevance", "resolution", "newest", "popular"],
                  "safe": "filter", "key": "optional", "formats": ["jpg", "png"], "nativeRu": False,
                  "limits": "45 requests per minute", "keyUrl": "https://wallhaven.cc/settings/account"},
    "commons": {"name": "Wikimedia Commons", "kinds": ["image", "animated", "video"], "sorts": ["relevance", "resolution", "newest"],
                "safe": "none", "key": "none", "formats": ["jpg", "png", "webp", "gif", "webm"], "nativeRu": False,
                "limits": "fair use, no hard quota", "keyUrl": ""},
    "openverse": {"name": "Openverse", "kinds": ["image", "animated"], "sorts": ["relevance", "resolution"],
                  "safe": "filter", "key": "none", "formats": ["jpg", "png", "gif"], "nativeRu": False,
                  "limits": "anonymous: about 100 requests per day", "keyUrl": ""},
    "pexels": {"name": "Pexels", "kinds": ["image", "video"], "sorts": ["relevance", "resolution"],
               "safe": "policy", "key": "required", "formats": ["jpg", "png", "mp4"], "nativeRu": True,
               "limits": "200 requests per hour, 20 000 per month", "keyUrl": "https://www.pexels.com/api/new/"},
    "pixabay": {"name": "Pixabay", "kinds": ["image", "video"], "sorts": ["relevance", "resolution", "newest", "popular"],
                "safe": "filter", "key": "required", "formats": ["jpg", "png", "mp4"], "nativeRu": True,
                "limits": "100 requests per minute; images over 1280 px need full API access", "keyUrl": "https://pixabay.com/api/docs/"},
    "giphy": {"name": "GIPHY", "kinds": ["animated"], "sorts": ["relevance"],
              "safe": "filter", "key": "required", "formats": ["gif"], "nativeRu": False,
              "limits": "separate browsing only; beta key: 100 requests per hour", "keyUrl": "https://developers.giphy.com/dashboard/"},
}
# The CLI's default stays focused on the internet providers. The UI explicitly
# supplies the enabled sources and library directories.
ALL_SOURCES = tuple(s for s in CAPS if s not in ("local", "links", "steam", "giphy"))
SORTS = ("relevance", "resolution", "newest", "popular")


class Ctx(object):
    """Parameters of one source request."""

    def __init__(self, **kw):
        self.__dict__.update(kw)


def web_url(value):
    if not isinstance(value, str) or not value or re.search(r"[\x00-\x20\\]", value):
        return ""
    try:
        url = urllib.parse.urlsplit(value)
        host = (url.hostname or "").rstrip(".").lower()
        if url.scheme not in ("https", "http") or not host or url.username is not None or url.password is not None:
            return ""
        try:
            if not ipaddress.ip_address(host).is_global:
                return ""
        except ValueError:
            if "." not in host or host.endswith((".local", ".localhost", ".internal")):
                return ""
        return value
    except ValueError:
        pass
    return ""


def url_id(url):
    return hashlib.sha256(url.encode("utf-8")).hexdigest()[:24]


def safe_duration(value):
    if isinstance(value, (int, float)):
        return max(0, value)
    if isinstance(value, str) and re.fullmatch(r"\d+(?::\d{1,2}){0,2}", value):
        return sum(int(part) * 60 ** i for i, part in enumerate(reversed(value.split(":"))))
    return 0


def brave_request(c, endpoint, **params):
    params.update(country="ALL", search_lang=c.lang, safesearch="strict" if c.safe else "off")
    params["q"] = " ".join(params["q"].split()[:50])[:400]
    return http_get("https://api.search.brave.com/res/v1/" + endpoint + "/search?" + urllib.parse.urlencode(params),
                    {"X-Subscription-Token": c.keys["brave"]})


def src_general_images(c):
    # The official image endpoint has count but no offset.
    if c.page != 1:
        return [], False, None
    query = " ".join(c.q.split()[:43])[:335] + " (filetype:gif OR filetype:webp OR filetype:apng)" if c.kind == "animated" else c.q
    d = brave_request(c, "images", q=query, count=48)
    out = []
    for r in d.get("results") or []:
        props, thumb = r.get("properties") or {}, r.get("thumbnail") or {}
        direct, page = web_url(props.get("url")), web_url(r.get("url"))
        poster = web_url(thumb.get("src"))
        fmt = ext_from(url=direct)
        if not (direct or page) or fmt in ("mp4", "webm"):
            continue
        out.append(item(
            id="brave:i:" + url_id(direct or page), source="brave", sourceName="Brave Images",
            title=strip_html(r.get("title")), pageUrl=page, thumb=poster, preview=poster,
            url=direct, width=int(props.get("width") or 0), height=int(props.get("height") or 0),
            format=fmt, originalAvailable=bool(direct), external=not direct))
    return out, False, None


def src_general_videos(c):
    if not 1 <= c.page <= 10:
        return [], False, None
    d = brave_request(c, "videos", q=c.q, count=PER_PAGE, offset=c.page - 1)
    out = []
    rows = d.get("results") or []
    for r in rows:
        page = web_url(r.get("url"))
        if not page:
            continue
        md = r.get("video") or {}
        thumb = web_url((r.get("thumbnail") or {}).get("src"))
        fmt = ext_from(url=page)
        direct = fmt in ("mp4", "webm") and not md.get("requires_subscription")
        out.append(item(
            id="brave:v:" + url_id(page), source="brave", sourceName="Brave Videos",
            title=strip_html(r.get("title")), pageUrl=page, url=page if direct else "",
            thumb=thumb, preview=thumb, kind="video", format=fmt if direct else "",
            duration=safe_duration(md.get("duration")), author=md.get("creator") or md.get("publisher") or "",
            originalAvailable=direct, external=not direct))
    return out, len(rows) >= PER_PAGE and c.page < 10, None


def src_brave(c):
    if not c.keys.get("brave"):
        return None, False, "needs a Brave Search API key"
    if c.kind == "video" or c.page > 1:
        return src_general_videos(c) if c.kind in ("all", "video") else ([], False, None)
    if c.kind != "all":
        return src_general_images(c)
    out, more, errors = [], False, []
    for name, search in (("Images", src_general_images), ("Videos", src_general_videos)):
        try:
            batch, has_more, _ = search(c)
            out.extend(batch)
            more = more or has_more
        except (SourceError, Offline) as e:
            errors.append((name, e))
    if len(errors) == 2:
        raise next((err for _, err in errors if isinstance(err, SourceError)), errors[0][1])
    return out, more, "; ".join("%s: %s" % (name, err) for name, err in errors) or None


def src_sepia(c):
    start = (c.page - 1) * PER_PAGE
    params = {"search": c.q, "start": start, "count": PER_PAGE, "nsfw": "false" if c.safe else "both"}
    d = http_get("https://sepiasearch.org/api/v1/search/videos?" + urllib.parse.urlencode(params))
    out = []
    for v in d.get("data") or []:
        page = web_url(v.get("url"))
        if not page or v.get("isLive") or (c.safe and v.get("nsfw") is not False):
            continue
        thumb = web_url(v.get("thumbnailUrl") or urllib.parse.urljoin(page, v.get("thumbnailPath") or ""))
        if thumb == page:
            thumb = ""
        out.append(item(
            id="sepia:" + url_id(page), source="sepia", sourceName="Sepia Search / PeerTube",
            title=v.get("name") or "", pageUrl=page, thumb=thumb, preview=thumb, kind="video",
            duration=safe_duration(v.get("duration")), originalAvailable=False, external=True,
            peerId=str(v.get("uuid") or "")))
    return out, start + PER_PAGE < int(d.get("total") or 0), None


def cmd_peertube(a):
    page = web_url(a.page_url)
    if not page or not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", a.uuid):
        raise SourceError("invalid PeerTube video")
    origin = urllib.parse.urlsplit(page)
    if origin.scheme != "https":
        raise SourceError("PeerTube metadata requires HTTPS")
    endpoint = "https://" + origin.netloc + "/api/v1/videos/" + a.uuid
    with open_media(endpoint, timeout=8, headers={"Accept": "application/json"}) as response:
        data = json.loads(response.read(2097152))
    if (data.get("privacy") or {}).get("id") != 1 or data.get("isLive") or data.get("downloadEnabled") is not True:
        emit({"ok": True, "media": {}})
        return
    if a.safe and data.get("nsfw") is not False:
        emit({"ok": True, "media": {}})
        return

    files = list(data.get("files") or [])
    for playlist in data.get("streamingPlaylists") or []:
        files.extend(playlist.get("files") or [])
    options = []
    for f in files:
        play, download = web_url(f.get("fileUrl")), web_url(f.get("fileDownloadUrl"))
        fmt = ext_from(url=play) or ext_from(url=download)
        if not download or fmt not in ("mp4", "webm") or f.get("hasVideo") is False:
            continue
        options.append({"url": download, "play": play, "format": fmt, "width": int(f.get("width") or 0),
                        "height": int(f.get("height") or 0), "size": int(f.get("size") or 0),
                        "fps": float(f.get("fps") or 0)})
    if not options:
        emit({"ok": True, "media": {}})
        return
    best = max(options, key=lambda f: (f["width"] * f["height"], f["size"]))
    small = pick_preview_rendition([f for f in options if f != best and f["play"] and 0 < f["width"] <= 1280])
    preview = small["play"] if small else ""
    if preview:
        try:
            require_public_url(preview)
        except (OSError, SourceError):
            preview = ""
    media = {k: best[k] for k in ("url", "format", "width", "height", "size", "fps")}
    media.update(external=False, originalAvailable=False, previewVideo=preview,
                 qualityKnown=bool(best["width"] and best["height"] and best["size"]),
                 notes=["PeerTube allows downloading this web rendition."])
    emit({"ok": True, "media": media})


def load_custom_sources():
    default = {"folders": [], "urls": []}
    saved = read_json(SOURCES_FILE, default)
    if not isinstance(saved, dict):
        return default
    for name in default:
        values = saved.get(name)
        if isinstance(values, list):
            default[name] = [v for v in values if isinstance(v, str) and v][:12]
    return default


def normalized_words(value):
    return re.findall(r"[^\W_]+", value.casefold())


def matches_query(text, query):
    normalized = " ".join(normalized_words(text))
    return all(word in normalized for word in normalized_words(query))


def src_local(c):
    if not c.dirs:
        return [], False, "connect a wallpaper folder"
    rows = []
    entries = local_items(c.dirs, query=c.q, kind=c.kind)
    if c.sort == "newest":
        entries.sort(key=lambda it: -it["mtime"])
    for it in entries:
        rows.append(item(id=it["id"] or "local:" + url_id(it["path"]), local=True, path=it["path"],
                         source="local", sourceName=it["source"] or "My Wallpapers", title=it["title"],
                         pageUrl=web_url(it.get("pageUrl")), size=it["size"], format=it["format"], kind=it["kind"],
                         width=it["width"], height=it["height"]))
    start = (c.page - 1) * PER_PAGE
    return rows[start:start + PER_PAGE], len(rows) > start + PER_PAGE, None


def feed_entries(url):
    with open_media(url, timeout=6) as response:
        body = response.read(1048577)
    if len(body) > 1048576:
        raise SourceError("feed exceeds the 1 MB size limit")
    if body.lstrip().startswith(b"{"):
        feed = json.loads(body)
        if not str(feed.get("version", "")).startswith("https://jsonfeed.org/version/"):
            raise SourceError("expected a JSON Feed")
        for post in (feed.get("items") or [])[:400]:
            for attachment in (post.get("attachments") or [])[:10]:
                yield (post.get("title") or "", post.get("url") or "", attachment.get("url") or "",
                       attachment.get("mime_type") or "", post.get("image") or "")
        return
    # RSS/Atom enclosures use no DTD or entity declarations.
    data = body.decode("utf-8-sig")
    if re.search(r"<!\s*(DOCTYPE|ENTITY)", data, re.IGNORECASE):
        raise SourceError("feed contains a prohibited XML declaration")
    root = ET.fromstring(data)
    if root.tag.rsplit("}", 1)[-1] not in ("rss", "feed"):
        raise SourceError("expected RSS/Atom or JSON Feed")
    for post in (list(root.iter("item")) + list(root.findall("{*}entry")))[:400]:
        title = post.findtext("{*}title") or ""
        links = post.findall("{*}link")
        page = next((l.get("href") or l.text for l in links if l.get("rel") in (None, "alternate")), "") or ""
        media = [(e.get("url"), e.get("type")) for e in post.findall("enclosure")]
        media += [(l.get("href"), l.get("type")) for l in links if l.get("rel") == "enclosure"]
        for target, mime in media[:10]:
            if target:
                yield title, page, target, mime or "", ""


def link_rows(url, query):
    fmt = ext_from(url=url)
    entries = [(urllib.parse.unquote(urllib.parse.urlsplit(url).path.rsplit("/", 1)[-1]), url, url, "", "")] if fmt else feed_entries(url)
    for title, page, target, mime, poster in entries:
        direct = web_url(urllib.parse.urljoin(url, target)) if target else ""
        fmt = ext_from(mime, direct)
        if not direct or not fmt or not matches_query(title + " " + urllib.parse.unquote(urllib.parse.urlsplit(direct).path), query):
            continue
        thumb = web_url(urllib.parse.urljoin(url, poster)) if poster else ""
        yield item(id="link:" + url_id(direct), source="links", sourceName="Custom URL", title=strip_html(title),
                   url=direct, pageUrl=web_url(urllib.parse.urljoin(url, page)) if page else url,
                   format=fmt, thumb=thumb, preview=thumb)


def src_links(c):
    if not c.urls:
        return [], False, "add a direct URL or feed in Sources"
    rows, errors = {}, []
    for url in c.urls:
        try:
            if not web_url(url):
                raise SourceError("invalid source URL")
            for row in link_rows(url, c.q):
                rows[row["id"]] = row
        except (OSError, SourceError, ValueError, AttributeError, TypeError, ET.ParseError, http.client.HTTPException):
            host = urllib.parse.urlsplit(url).hostname or "feed"
            errors.append(host)
    if len(errors) == len(c.urls):
        raise SourceError("could not read custom sources: " + ", ".join(errors))
    rows = list(rows.values())
    start = (c.page - 1) * PER_PAGE
    return rows[start:start + PER_PAGE], len(rows) > start + PER_PAGE, ("could not read " + ", ".join(errors)) if errors else None


def src_steam(c):
    params = {"appid": 431960, "creator_appid": 431960, "query_type": 1 if c.sort == "newest" else 12,
              "page": c.page, "numperpage": PER_PAGE, "search_text": c.q, "requiredtags": ["Video"],
              "return_previews": True}
    d = http_get("https://api.steampowered.com/IPublishedFileService/QueryFiles/v1/?" +
                 urllib.parse.urlencode({"input_json": json.dumps(params)}), {"x-webapi-key": c.keys["steam"]})
    result = d.get("response") or {}
    rows = []
    for row in result.get("publishedfiledetails") or []:
        ident = str(row.get("publishedfileid") or "")
        if not ident.isdecimal() or row.get("banned"):
            continue
        thumb = web_url(row.get("preview_url"))
        rows.append(item(id="steam:" + ident, source="steam", sourceName="Steam Workshop",
                         title=row.get("title") or "", pageUrl="https://steamcommunity.com/sharedfiles/filedetails/?id=" + ident,
                         thumb=thumb, preview=thumb, kind="video", external=True, originalAvailable=False))
    return rows, c.page < 1000 and c.page * PER_PAGE < int(result.get("total") or 0), None


def landscape_px(minres):
    return minres[0] * minres[1]


def src_wallhaven(c):
    if c.kind in ("animated", "video"):
        return [], False, "Wallhaven hosts still images only"
    sorting = {"relevance": "relevance", "resolution": "relevance", "newest": "date_added", "popular": "favorites"}[c.sort]
    # purity 100 = SFW only. Without Safe Search we add "sketchy" (110); the NSFW
    # category is never requested.
    params = {"q": c.q, "page": c.page, "sorting": sorting, "order": "desc", "categories": "111",
              "purity": "100" if c.safe else "110"}
    if c.minres[0]:
        params["atleast"] = "%dx%d" % c.minres
    if c.keys.get("wallhaven"):
        params["apikey"] = c.keys["wallhaven"]
    d = http_get("https://wallhaven.cc/api/v1/search?" + urllib.parse.urlencode(params))
    out = []
    for w in d.get("data") or []:
        fmt = ext_from(w.get("file_type"), w.get("path"))
        src = (w.get("source") or "").strip()
        out.append(item(
            id="wallhaven:" + w.get("id", ""), source="wallhaven", sourceName="Wallhaven",
            title=(w.get("category") or "wallpaper").capitalize() + " " + w.get("id", ""),
            pageUrl=w.get("url", ""), thumb=(w.get("thumbs") or {}).get("small", ""),
            preview=(w.get("thumbs") or {}).get("large", ""), url=w.get("path", ""),
            width=int(w.get("dimension_x") or 0), height=int(w.get("dimension_y") or 0),
            format=fmt, size=int(w.get("file_size") or 0),
            created=(w.get("created_at") or "").replace(" ", "T"),
            favorites=int(w.get("favorites") or 0), views=int(w.get("views") or 0),
            provenance="unknown",
            provenanceReason=("Uploader cites an origin (" + src + "), but Wallhaven does not verify it." if src
                              else "Community upload without a stated origin."),
            sourceLink=src))
    meta = d.get("meta") or {}
    return out, int(meta.get("current_page") or c.page) < int(meta.get("last_page") or 0), None


def src_commons(c):
    terms = [c.q]
    if c.kind == "video":
        terms.append("filetype:video")
    elif c.kind == "animated":
        terms.append("filemime:image/gif")
    elif c.kind == "image":
        terms.append("filetype:bitmap")
    else:
        terms.append("filetype:bitmap|video")
    video_search = c.kind == "video"
    params = {
        "action": "query", "format": "json", "generator": "search", "gsrnamespace": "6",
        "gsrsearch": " ".join(terms), "gsrlimit": PER_PAGE, "gsroffset": (c.page - 1) * PER_PAGE,
        "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata|timestamp", "iiurlwidth": "480",
        "iiextmetadatafilter": "Artist|LicenseShortName|Credit|ObjectName",
    }
    if video_search:
        params["prop"] = "videoinfo"
        for key in ("prop", "urlwidth", "extmetadatafilter"):
            params["vi" + key] = params.pop("ii" + key)
        params["viprop"] += "|derivatives|dimensions"
    if c.sort == "newest":
        params["gsrsort"] = "create_timestamp_desc"
    d = http_get("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params))
    if d.get("error"):
        raise SourceError(str(d["error"].get("info") or d["error"]))
    pages = sorted(((d.get("query") or {}).get("pages") or {}).values(), key=lambda p: p.get("index", 0))
    out = []
    for p in pages:
        ii = (p.get("videoinfo" if video_search else "imageinfo") or [{}])[0]
        fmt = ext_from(ii.get("mime"), ii.get("url"))
        original = web_url(ii.get("url"))
        w, h = int(ii.get("width") or 0), int(ii.get("height") or 0)
        size = int(ii.get("size") or 0)
        video = video_search or fmt in ("mp4", "webm")
        rendition = None
        preview_video = ""
        if video:
            files = [{"url": web_url(f.get("src")), "format": ext_from(f.get("type"), f.get("src")),
                      "width": int(f.get("width") or 0), "height": int(f.get("height") or 0)}
                     for f in ii.get("derivatives") or []]
            files = [f for f in files if f["url"] and f["url"] != original and f["width"] > 0 and f["format"] in ("mp4", "webm")]
            if fmt not in ("mp4", "webm") or not original:
                rendition = max(files, key=lambda f: f["width"] * f["height"], default=None)
                original, fmt, w, h, size = (rendition["url"], rendition["format"], rendition["width"], rendition["height"], 0) if rendition else ("", "", w, h, 0)
            small = pick_preview_rendition([f for f in files if f["url"] != original and f["width"] <= 1280])
            preview_video = small["url"] if small else ""
        elif fmt not in MEDIA_EXT:
            continue
        md = ii.get("extmetadata") or {}

        def val(k):
            return strip_html((md.get(k) or {}).get("value", ""))
        credit = val("Credit")
        own = "own work" in credit.lower()
        title = val("ObjectName") or re.sub(r"^File:|\.[A-Za-z0-9]+$", "", p.get("title", ""))
        thumb = ii.get("thumburl", "")
        out.append(item(
            id="commons:%s" % p.get("pageid"), source="commons", sourceName="Wikimedia Commons",
            title=title, pageUrl=ii.get("descriptionurl", ""), thumb=thumb,
            preview=thumb, previewVideo=preview_video,
            url=original, width=w, height=h, external=not original, originalAvailable=bool(original and not rendition),
            format=fmt, kind="video" if video else "", size=size, duration=float(ii.get("duration") or 0),
            created=ii.get("timestamp", ""),
            author=val("Artist"), license=val("LicenseShortName"),
            provenance="verified" if own else "unknown",
            provenanceReason=("Commons records the uploader as the author (\"Own work\"), license " + val("LicenseShortName") + "."
                              if own else "Commons file; credit: " + (credit or "not stated") + ". Not confirmed as the original upload.")))
    return out, "continue" in d, None


def src_openverse(c):
    if c.kind == "video":
        return [], False, "Openverse has no video search"
    params = {"q": c.q, "page": c.page, "page_size": 20, "mature": "false" if c.safe else "true"}
    if c.minres[0] >= 1920:
        params["size"] = "large"
    if c.minres[0]:
        params["aspect_ratio"] = "wide"
    if c.kind == "animated":
        params["extension"] = "gif"
    d = http_get("https://api.openverse.org/v1/images/?" + urllib.parse.urlencode(params))
    out = []
    for r in d.get("results") or []:
        fmt = ext_from("", r.get("url")) or (r.get("filetype") or "").lower().replace("jpeg", "jpg")
        if fmt not in MEDIA_EXT:
            continue
        w, h = int(r.get("width") or 0), int(r.get("height") or 0)
        out.append(item(
            id="openverse:" + r.get("id", ""), source="openverse", sourceName="Openverse / " + (r.get("source") or r.get("provider") or "?"),
            # Openverse answers browser-like clients (Qt's "Mozilla/5.0") with HTTP 403;
            # its thumbnails are fetched by this helper with its own User-Agent instead.
            title=r.get("title") or "", pageUrl=r.get("foreign_landing_url", ""), thumb=r.get("thumbnail", ""), thumbHelper=True,
            preview=r.get("thumbnail", ""), url=r.get("url", ""), width=w, height=h, format=fmt,
            size=int(r.get("filesize") or 0), author=r.get("creator") or "",
            license=((r.get("license") or "").upper() + " " + (r.get("license_version") or "")).strip(),
            provenance="unknown",
            provenanceReason="Openverse indexes the file from " + (r.get("source") or "a third-party site") + "; it does not verify the original upload."))
    return out, int(d.get("page_count") or 0) > c.page, None


def pick_preview_rendition(files, min_width=640):
    """Smallest rendition that is still watchable: previews never stream the 4K original."""
    usable = [f for f in files if int(f.get("width") or 0) >= min_width]
    pool = usable or files
    return min(pool, key=lambda f: int(f.get("width") or 0) * int(f.get("height") or 0)) if pool else None


def src_pexels(c):
    key = c.keys.get("pexels")
    if not key:
        return None, False, "needs a free Pexels API key"
    if c.kind == "animated":
        return [], False, "Pexels has no GIF animations"
    hdr = {"Authorization": key}
    locale = "ru-RU" if c.lang == "ru" else "en-US"
    out, more = [], False
    if c.kind in ("all", "image"):
        params = {"query": c.q, "page": c.page, "per_page": PER_PAGE, "locale": locale}
        if c.minres[0]:
            params["orientation"] = "landscape"
        # Pexels size classes: small >= 4 MP, medium >= 12 MP, large >= 24 MP. Only a
        # class that is a superset of the requested resolution is sent.
        if landscape_px(c.minres) >= 24000000:
            params["size"] = "large"
        elif landscape_px(c.minres) >= 4000000:
            params["size"] = "small"
        d = http_get("https://api.pexels.com/v1/search?" + urllib.parse.urlencode(params), hdr)
        for p in d.get("photos") or []:
            src = p.get("src") or {}
            out.append(item(
                id="pexels:p%s" % p.get("id"), source="pexels", sourceName="Pexels",
                title=p.get("alt") or "Pexels photo %s" % p.get("id"), pageUrl=p.get("url", ""),
                thumb=src.get("medium", ""), preview=src.get("large2x", ""), url=src.get("original", ""),
                width=int(p.get("width") or 0), height=int(p.get("height") or 0), format=ext_from("", src.get("original")) or "jpg",
                author=p.get("photographer", ""), license="Pexels License", provenance="verified",
                provenanceReason="Original upload by the photographer (" + (p.get("photographer") or "?") + ") on Pexels.",
                notes=["Pexels reports the file size only after download."]))
        more = more or bool(d.get("next_page"))
    if c.kind in ("all", "video"):
        params = {"query": c.q, "page": c.page, "per_page": PER_PAGE, "locale": locale}
        if c.minres[0]:
            params["min_width"], params["min_height"] = c.minres
            params["orientation"] = "landscape"
        d = http_get("https://api.pexels.com/videos/search?" + urllib.parse.urlencode(params), hdr)
        for v in d.get("videos") or []:
            files = [f for f in (v.get("video_files") or [])
                     if ext_from(f.get("file_type"), f.get("link")) in ("mp4", "webm") and web_url(f.get("link"))]
            files.sort(key=lambda f: (int(f.get("width") or 0) * int(f.get("height") or 0), float(f.get("fps") or 0)), reverse=True)
            if not files:
                continue
            best = files[0]
            small = pick_preview_rendition([f for f in files[1:] if 0 < int(f.get("width") or 0) <= 1280])
            pics = v.get("video_pictures") or []
            slug = urllib.parse.urlparse(v.get("url", "")).path.strip("/").split("/")[-1]
            out.append(item(
                id="pexels:v%s" % v.get("id"), source="pexels", sourceName="Pexels Video",
                title=re.sub(r"[-\d]+$", "", slug).replace("-", " ").strip() or "Pexels video",
                pageUrl=v.get("url", ""), thumb=(pics[0].get("picture") if pics else v.get("image", "")), preview=v.get("image", ""),
                previewVideo=small.get("link", "") if small else "",
                url=best.get("link", ""), width=int(best.get("width") or 0), height=int(best.get("height") or 0),
                format=ext_from(best.get("file_type"), best.get("link")) or "mp4", fps=round(float(best.get("fps") or 0), 3),
                size=int(best.get("size") or 0), duration=float(v.get("duration") or 0),
                author=(v.get("user") or {}).get("name", ""), license="Pexels License", provenance="verified",
                provenanceReason="Uploaded by the author on Pexels; this is the largest rendition Pexels serves."))
        more = more or bool(d.get("next_page"))
    return out, more, None


def src_pixabay(c):
    key = c.keys.get("pixabay")
    if not key:
        return None, False, "needs a free Pixabay API key"
    if c.kind == "animated":
        return [], False, "Pixabay's API serves no animations"
    out, more = [], False
    base = {"key": key, "q": c.q[:100], "page": c.page, "per_page": PER_PAGE, "safesearch": "true" if c.safe else "false",
            "lang": "ru" if c.lang == "ru" else "en"}
    if c.sort == "newest":
        base["order"] = "latest"
    elif c.sort == "popular":
        base["order"] = "popular"
    if c.minres[0]:
        base["min_width"], base["min_height"] = c.minres
    if c.kind in ("all", "image"):
        params = dict(base)
        if c.minres[0]:
            params["orientation"] = "horizontal"
        d = http_get("https://pixabay.com/api/?" + urllib.parse.urlencode(params))
        for h in d.get("hits") or []:
            full = h.get("imageURL") or ""
            iw, ih = int(h.get("imageWidth") or 0), int(h.get("imageHeight") or 0)
            if full:
                url, w, hh, note, orig = full, iw, ih, [], True
            else:
                url = h.get("largeImageURL", "")
                s = min(1.0, 1280.0 / max(iw, ih, 1))
                w, hh, orig = int(round(iw * s)), int(round(ih * s)), False
                note = ["Pixabay serves at most 1280 px without full API access; the %dx%d original is not downloadable here." % (iw, ih)]
            out.append(item(
                id="pixabay:i%s" % h.get("id"), source="pixabay", sourceName="Pixabay",
                title=h.get("tags") or "Pixabay image", pageUrl=h.get("pageURL", ""), thumb=h.get("previewURL", ""),
                preview=h.get("webformatURL", ""), url=url, width=w, height=hh, format=ext_from("", url) or "jpg",
                size=int(h.get("imageSize") or 0) if orig else 0, author=h.get("user", ""), license="Pixabay Content License",
                downloads=int(h.get("downloads") or 0), likes=int(h.get("likes") or 0),
                provenance="verified", provenanceReason="Uploaded by " + (h.get("user") or "?") + " on Pixabay.",
                notes=note, originalAvailable=orig))
        more = more or c.page * PER_PAGE < int(d.get("totalHits") or 0)
    if c.kind in ("all", "video"):
        d = http_get("https://pixabay.com/api/videos/?" + urllib.parse.urlencode(base))
        for v in d.get("hits") or []:
            vids = v.get("videos") or {}
            files = [vids[k] for k in ("large", "medium", "small", "tiny") if (vids.get(k) or {}).get("url") and int((vids.get(k) or {}).get("width") or 0) > 0]
            if not files:
                continue
            best = files[0]
            small = pick_preview_rendition([f for f in files[1:] if int(f["width"]) <= 1280])
            out.append(item(
                id="pixabay:v%s" % v.get("id"), source="pixabay", sourceName="Pixabay Video",
                title=v.get("tags") or "Pixabay video", pageUrl=v.get("pageURL", ""), thumb=best.get("thumbnail", ""),
                preview=best.get("thumbnail", ""), previewVideo=small.get("url", "") if small else "",
                url=best.get("url", ""), width=int(best.get("width") or 0),
                height=int(best.get("height") or 0), format="mp4", size=int(best.get("size") or 0),
                duration=float(v.get("duration") or 0), author=v.get("user", ""), license="Pixabay Content License",
                downloads=int(v.get("downloads") or 0), likes=int(v.get("likes") or 0),
                provenance="verified", provenanceReason="Uploaded by " + (v.get("user") or "?") + " on Pixabay."))
        more = more or c.page * PER_PAGE < int(d.get("totalHits") or 0)
    return out, more, None


def src_giphy(c):
    key = c.keys.get("giphy")
    if not key:
        return None, False, "needs a Giphy API key"
    if c.kind not in ("all", "animated"):
        return [], False, "Giphy hosts GIF animations only"
    offset = (c.page - 1) * PER_PAGE
    if offset > 4999:
        return [], False, None
    params = {"api_key": key, "q": c.q, "limit": PER_PAGE, "offset": offset, "rating": "pg" if c.safe else "r"}
    d = http_get("https://api.giphy.com/v1/gifs/search?" + urllib.parse.urlencode(params))
    out = []
    for g in d.get("data") or []:
        im = g.get("images") or {}
        o = im.get("original") or {}
        frames = int(o.get("frames") or 0)
        out.append(item(
            id="giphy:" + g.get("id", ""), source="giphy", sourceName="Giphy", title=g.get("title", ""),
            pageUrl=g.get("url", ""), thumb=(im.get("fixed_width_still") or {}).get("url", ""),
            preview=(im.get("fixed_width") or {}).get("url", ""), external=True, originalAvailable=False,
            previewAnimation=(im.get("fixed_width") or {}).get("url", ""), animationFrames=frames,
            width=int(o.get("width") or 0), height=int(o.get("height") or 0), format="gif",
            size=int(o.get("size") or 0), created=(g.get("import_datetime") or "").replace(" ", "T"),
            author=(g.get("user") or {}).get("display_name", "") or g.get("username", ""),
            provenance="unknown", provenanceReason="Giphy does not state the origin of the animation."))
    pg = d.get("pagination") or {}
    return out, int(pg.get("offset") or 0) + int(pg.get("count") or 0) < int(pg.get("total_count") or 0), None


SOURCE_FUNCS = {"brave": src_brave, "sepia": src_sepia, "local": src_local, "links": src_links, "steam": src_steam,
                "wallhaven": src_wallhaven, "commons": src_commons, "openverse": src_openverse,
                "pexels": src_pexels, "pixabay": src_pixabay, "giphy": src_giphy}


def plan_skip(name, kind, sort, safe, keys):
    """Why a source cannot take part in this search, as (code, text), or None."""
    cap = CAPS[name]
    if kind != "all" and kind not in cap["kinds"]:
        return "kind", "%s has no %s" % (cap["name"], {"image": "still images", "animated": "animations", "video": "videos"}[kind])
    if sort not in cap["sorts"]:
        return ("sort-" + sort, "%s does not provide %s" % (cap["name"], "upload dates" if sort == "newest" else "reliable popularity data"))
    if safe and cap["safe"] == "none":
        return "safe", "%s has no safe-search filter; it is used only with Safe Search off" % cap["name"]
    if cap["key"] == "required" and not keys.get(name):
        return "key", "needs your own %s API key" % cap["name"]
    return None


def gif_frames(stream, header):
    """Count up to two complete image blocks, ignoring comments and other extensions."""
    def skip_blocks():
        while True:
            length = stream.read(1)
            if not length:
                return False
            if length == b"\0":
                return True
            if len(stream.read(length[0])) != length[0]:
                return False

    if len(header) < 13:
        return 0
    if header[10] & 0x80:
        stream.seek(3 * (2 << (header[10] & 7)), io.SEEK_CUR)
    frames = 0
    while frames < 2:
        marker = stream.read(1)
        if marker == b";":
            return frames
        if marker == b"!":
            if not stream.read(1) or not skip_blocks():
                break
        elif marker == b",":
            descriptor = stream.read(9)
            if len(descriptor) != 9:
                break
            if descriptor[8] & 0x80:
                stream.seek(3 * (2 << (descriptor[8] & 7)), io.SEEK_CUR)
            if not stream.read(1) or not skip_blocks():
                break
            frames += 1
        else:
            break
    return frames if frames >= 2 else 0


def animation_frames(stream, fmt):
    """Inspect container metadata, with no image decoding. Zero means unconfirmed."""
    if fmt == "gif":
        header = stream.read(13)
        return gif_frames(stream, header) if sniff(header) == "gif" else 0
    if fmt in ("png", "apng"):
        if sniff(stream.read(8)) != "png":
            return 0
        while chunk := stream.read(8):
            if len(chunk) != 8:
                return 0
            size, label = int.from_bytes(chunk[:4], "big"), chunk[4:]
            if label == b"acTL" and size == 8:
                return int.from_bytes(stream.read(4), "big")
            if label in (b"IDAT", b"IEND"):
                return 1
            stream.seek(size + 4, io.SEEK_CUR)
        return 0
    if fmt == "webp":
        header = stream.read(12)
        if sniff(header) != "webp":
            return 0
        end = int.from_bytes(header[4:8], "little") + 8
        frames = 0
        while stream.tell() + 8 <= end:
            chunk = stream.read(8)
            if len(chunk) != 8:
                return 0
            label, size = chunk[:4], int.from_bytes(chunk[4:], "little")
            skip = size + size % 2
            if stream.tell() + skip > end:
                return 0
            if label == b"VP8X" and size == 10:
                if not (int.from_bytes(stream.read(1), "little") & 2):
                    return 1
                skip -= 1
            if label in (b"VP8 ", b"VP8L"):
                return 1
            if label == b"ANMF" and size >= 16:
                frames += 1
            stream.seek(skip, io.SEEK_CUR)
            if frames >= 2:
                return frames
        return frames
    return 1


class MediaRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        require_public_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def require_public_url(url):
    if not web_url(url):
        raise SourceError("only public HTTP(S) media URLs are allowed")
    host = urllib.parse.urlsplit(url).hostname
    addresses = {entry[4][0] for entry in socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)}
    if not addresses or any(not ipaddress.ip_address(address).is_global for address in addresses):
        raise SourceError("media server does not resolve exclusively to public addresses")


def open_media(url, *, timeout, headers=None):
    require_public_url(url)
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    return urllib.request.build_opener(MediaRedirect()).open(req, timeout=timeout)


def resolve_animation(result):
    """An animated original can have a completely static thumbnail."""
    fmt = result["format"]
    if result["animationFrames"]:
        frames = result["animationFrames"]
    else:
        frames = 0
        try:
            with open_media(result["url"], timeout=3, headers={"Range": "bytes=0-1048575"}) as response:
                data = response.read(1048576)
            frames = animation_frames(io.BytesIO(data), fmt)
        except (OSError, SourceError, http.client.HTTPException):
            pass
    result["animationFrames"] = frames
    result["kind"] = "animated" if frames > 1 else "image"
    result["animationUnconfirmed"] = frames == 0
    if frames > 1:
        if fmt == "png":
            result["format"] = "apng"
        result["previewAnimation"] = result["previewAnimation"] or result["url"]


def classify_animations(results, include_png=False):
    formats = ANIMATION_FORMATS | {"png"} if include_png else ANIMATION_FORMATS
    candidates = [r for r in results if r["url"] and r["format"] in formats]
    if candidates:
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, len(candidates))) as pool:
            list(pool.map(resolve_animation, candidates))


def guard(results, kind, minres, include_unknown=False):
    """Client-side checks for what a source could not filter itself.
    Returns the kept results and how many were hidden, by reason."""
    hidden = {"lowres": 0, "unknownRes": 0, "reducedCopy": 0, "kind": 0, "animation": 0}
    out = []
    for m in results:
        if kind == "animated" and m.get("animationUnconfirmed"):
            hidden["animation"] += 1
            continue
        if kind != "all" and m["kind"] != kind:
            hidden["kind"] += 1
            continue
        if minres[0]:
            if not (m["width"] and m["height"]) and not include_unknown:
                hidden["unknownRes"] += 1
                continue
            w, h = m["width"], m["height"]
            if w and h and (max(w, h) < minres[0] or min(w, h) < minres[1]):
                hidden["reducedCopy" if not m["originalAvailable"] else "lowres"] += 1
                continue
        out.append(m)
    return out, {k: v for k, v in hidden.items() if v}


def remember_query(query):
    items = [q for q in read_json(HISTORY_FILE, []) if isinstance(q, str) and q.strip().lower() != query.lower()]
    items.insert(0, query)
    ensure_private_dir(HUB_STATE)
    write_json_atomic(HISTORY_FILE, items[:HISTORY_MAX], mode=0o600)


def cmd_search(a):
    """Streams one JSON line per event so the UI shows each source as soon as it answers:
       {"event":"start", ...}  {"event":"source", ...} x N  {"event":"done", ...}"""
    query = (a.query or "").strip()
    if not query:
        emit({"event": "done", "ok": False, "error": "empty query"})
        return
    if a.sort not in SORTS:
        a.sort = "relevance"
    keys = load_keys()
    sources = load_custom_sources()
    minres = RES.get(a.min, (0, 0))
    wanted = [s for s in dict.fromkeys(a.sources.split(",") if a.sources is not None else ALL_SOURCES) if s in SOURCE_FUNCS]
    source_pages = json.loads(a.source_pages or "{}")
    if not isinstance(source_pages, dict):
        raise SourceError("invalid source pages")
    if a.source_pages:
        wanted = [s for s in wanted if isinstance(source_pages.get(s), int) and source_pages[s] > 0]
    lang = "ru" if has_cyrillic(query) else "en"
    plan, active = [], []
    for name in wanted:
        skip = ("separate", "Select GIPHY by itself to browse its GIFs") if name == "giphy" and len(wanted) != 1 else plan_skip(name, a.kind, a.sort, a.safe, keys)
        plan.append({"source": name, "skipCode": skip[0], "skipped": skip[1]} if skip else {"source": name})
        if not skip:
            active.append(name)
    translated, terr = None, None
    if lang == "ru" and a.translate == "auto" and any(not CAPS[s]["nativeRu"] for s in active):
        translated, terr = translate(query)
    for p in plan:
        if "skipped" not in p:
            p["query"] = query if (CAPS[p["source"]]["nativeRu"] or not translated) else translated
    if a.remember and a.page == 1:
        try:
            remember_query(query)
        except OSError:
            pass
    emit({"event": "start", "query": query, "lang": lang, "translated": translated, "translateError": terr,
          "page": a.page, "kind": a.kind, "min": a.min, "sort": a.sort, "safe": a.safe, "sources": plan})

    queries = {p["source"]: p.get("query", query) for p in plan}

    def run(name):
        native = CAPS[name]["nativeRu"]
        c = Ctx(q=queries[name], page=source_pages.get(name, a.page), kind=a.kind, minres=minres, keys=keys, safe=a.safe,
                lang=lang if (native or not translated) else "en", sort=a.sort, urls=sources["urls"],
                dirs=a.dir + sources["folders"])
        t0 = time.monotonic()
        try:
            res, more, note = SOURCE_FUNCS[name](c)
            if res and a.kind != "video" and name != "local":
                classify_animations(res, a.kind == "animated" and name in ("brave", "links"))
            return name, res, more, note, None, False, time.monotonic() - t0
        except Offline as e:
            return name, None, False, None, str(e), True, time.monotonic() - t0
        except SourceError as e:
            return name, None, False, None, str(e), False, time.monotonic() - t0
        except Exception as e:  # a malformed answer must not kill the whole search
            return name, None, False, None, "unexpected answer: %s" % e, False, time.monotonic() - t0

    qc = read_json(QUALITY_CACHE, {})
    any_more, offline_count = False, 0
    if active:
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(active)) as ex:
            futures = [ex.submit(run, n) for n in active]
            for f in concurrent.futures.as_completed(futures):
                name, res, more, note, err, off, dt = f.result()
                offline_count += 1 if off else 0
                st = {"source": name, "query": queries[name], "count": 0, "ms": int(dt * 1000),
                      "page": source_pages.get(name, a.page)}
                kept = []
                if err:
                    st["error"] = err
                    st["offline"] = off
                elif res is None:
                    st["skipped"] = note
                else:
                    kept, hidden = (res, {}) if name == "giphy" else guard(res, a.kind, minres, a.include_unknown)
                    for m in kept:
                        m["thumbCache"] = thumb_path(m["thumb"]) if m["thumb"] and name != "giphy" else ""
                        if name in ("brave", "sepia", "links", "steam"):
                            m["thumbHelper"] = True
                        m["thumbCached"] = bool(m["thumbCache"]) and os.path.exists(m["thumbCache"])
                        if m["id"] in qc:
                            m["quality"] = qc[m["id"]]
                    st["count"] = len(kept)
                    st["received"] = len(res)
                    if hidden:
                        st["hidden"] = hidden
                    if note:
                        st["note"] = note
                    elif not res:
                        st["note"] = "no results for this query"
                    st["hasMore"] = bool(more)
                    any_more = any_more or more
                emit({"event": "source", "source": name, "page": a.page, "status": st, "results": kept})
    remote_count = sum(s != "local" for s in active)
    emit({"event": "done", "ok": True, "query": query, "page": a.page, "hasMore": any_more,
          "offline": bool(remote_count) and offline_count == remote_count, "noActive": not active})


# --------------------------------------------------------------------------- thumbs

def thumb_path(url):
    h = hashlib.sha1(url.encode("utf-8")).hexdigest()
    return os.path.join(THUMB_DIR, h[:2], h + ".img")


def cmd_cache_thumbs(a):
    try:
        urls = json.loads(sys.stdin.readline() or "[]")  # one JSON line; never waits for EOF
    except ValueError:
        urls = []
    urls = [u for u in urls if isinstance(u, str) and u.startswith("https://")][:120]

    def fetch(u):
        p = thumb_path(u)
        if os.path.exists(p):
            return p, False
        try:
            with open_media(u, timeout=10) as response:
                body = response.read(4 * 1024 * 1024 + 1)
        except Exception:
            return "", False
        if len(body) > 4 * 1024 * 1024 or sniff(body[:64]) not in ("jpg", "png", "webp", "gif"):
            return "", False
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p + ".part", "wb") as f:
            f.write(body)
        os.replace(p + ".part", p)
        return p, True

    # One line per thumbnail as soon as it is ready (or failed), so cards fill in progressively.
    done = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
        futs = {ex.submit(fetch, u): u for u in urls}
        for f in concurrent.futures.as_completed(futs):
            path, fresh = f.result()
            done += fresh
            emit({"event": "thumb", "url": futs[f], "path": path.replace(os.sep, "/") if path else "", "failed": not path})
    prune_dir(THUMB_DIR, 300 * 1024 * 1024)
    emit({"ok": True, "cached": done})


def prune_dir(root, limit):
    files = []
    for dp, _, fns in os.walk(root):
        for fn in fns:
            p = os.path.join(dp, fn)
            try:
                st = os.stat(p)
                files.append((st.st_atime, st.st_size, p))
            except OSError:
                pass
    total = sum(f[1] for f in files)
    for _, size, p in sorted(files):
        if total <= limit:
            break
        try:
            os.remove(p)
            total -= size
        except OSError:
            pass


# --------------------------------------------------------------------------- media checks

def sniff(head):
    if head[:3] == b"\xff\xd8\xff":
        return "jpg"
    if head[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if head[:6] in (b"GIF87a", b"GIF89a"):
        return "gif"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "webp"
    if head[:4] == b"\x1a\x45\xdf\xa3":
        return "webm"  # Matroska/WebM container
    if head[4:8] == b"ftyp":
        return "mp4"
    return ""


def ffprobe(path):
    if not shutil.which("ffprobe"):
        return None, "ffprobe is not installed"
    try:
        r = subprocess.run(["ffprobe", "-v", "error", "-protocol_whitelist", "file", "-show_format", "-show_streams", "-of", "json", path],
                           capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        return None, "ffprobe timed out"
    if r.returncode != 0:
        return None, (r.stderr.strip().splitlines() or ["ffprobe could not read the file"])[-1]
    try:
        return json.loads(r.stdout), None
    except ValueError:
        return None, "ffprobe output unreadable"


def ratio(s):
    try:
        n, d = s.split("/")
        return float(n) / float(d) if float(d) else 0.0
    except (ValueError, AttributeError):
        return 0.0


def media_info(path):
    """Real technical parameters of a local file."""
    info = {"path": path, "size": 0, "format": "", "width": 0, "height": 0, "kind": "image"}
    try:
        info["size"] = os.path.getsize(path)
        with open(path, "rb") as f:
            head = f.read(64)
    except OSError as e:
        info["error"] = str(e)
        return info
    info["format"] = sniff(head)
    if not info["format"]:
        info["error"] = "not a supported image or video (unknown file signature)"
        return info
    d, err = ffprobe(path)
    if d is None:
        info["error"] = err
        return info
    vs = next((s for s in d.get("streams") or [] if s.get("codec_type") == "video"
               and not (s.get("disposition") or {}).get("attached_pic")), None)
    if not vs:
        info["error"] = "no picture stream found"
        return info
    fmt = d.get("format") or {}
    info["width"], info["height"] = int(vs.get("width") or 0), int(vs.get("height") or 0)
    if not info["width"] or not info["height"]:
        info["error"] = "picture has no size (damaged file)"
        return info
    info["codec"] = vs.get("codec_name", "")
    info["pixFmt"] = vs.get("pix_fmt", "")
    bits = str(vs.get("bits_per_raw_sample") or "")
    if not bits.isdigit():
        m = re.search(r"p(\d+)(le|be)$", info["pixFmt"] or "")
        bits = m.group(1) if m else ("8" if info["pixFmt"] else "")
    info["bitDepth"] = int(bits) if bits.isdigit() else 0
    tags = {}
    tags.update(fmt.get("tags") or {})
    tags.update(vs.get("tags") or {})
    info["tags"] = {k: str(v)[:200] for k, v in list(tags.items())[:20]}
    if info["format"] in ("mp4", "webm"):
        info["kind"] = "video"
        info["fps"] = round(ratio(vs.get("avg_frame_rate")) or ratio(vs.get("r_frame_rate")), 3)
        info["duration"] = float(fmt.get("duration") or vs.get("duration") or 0)
        br = int(vs.get("bit_rate") or 0) or int(fmt.get("bit_rate") or 0)
        if not br and info["duration"] > 0:
            br = int(info["size"] * 8 / info["duration"])
        info["bitrate"] = br
    elif info["format"] in ("gif", "webp", "png"):
        with open(path, "rb") as f:
            frames = animation_frames(f, info["format"])
        if info["format"] == "gif" or (info["format"] == "webp" and frames > 1):
            frames = count_frames(path)
        if not frames:
            info["error"] = "unable to read image frames"
            return info
        if info["format"] == "png" and frames > 1:
            info["format"] = "apng"
        info["frames"] = frames
        info["kind"] = "animated" if frames > 1 else "image"
        if frames > 1:
            info["duration"] = float(fmt.get("duration") or vs.get("duration") or 0)
            info["fps"] = round(ratio(vs.get("avg_frame_rate")), 3)
    return info


def count_frames(path):
    try:
        r = subprocess.run(["ffprobe", "-v", "error", "-protocol_whitelist", "file", "-select_streams", "v:0", "-count_frames",
                            "-show_entries", "stream=nb_read_frames", "-of", "csv=p=0", path],
                           capture_output=True, text=True, timeout=40)
        return int((r.stdout.strip().split(",")[0] or "0"))
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return 0


def cmd_probe(a):
    info = media_info(a.path)
    emit({"ok": not info.get("error"), "info": info, "error": info.get("error", "")})


# --------------------------------------------------------------------------- download

def safe_name(s):
    s = re.sub(r"[^\w\-]+", "_", s or "", flags=re.UNICODE).strip("_")
    return s[:60] or "wallpaper"


_partial = None


def _on_term(signum, frame):
    if _partial and os.path.exists(_partial):
        try:
            os.remove(_partial)
        except OSError:
            pass
    emit({"ok": False, "cancelled": True, "error": "download cancelled"})
    sys.exit(130)


def stream_media(source, target, limit, total):
    done, last = 0, 0.0
    while chunk := source.read(256 * 1024):
        done += len(chunk)
        if done > limit:
            raise SourceError("file exceeded the %d MB limit" % (limit // 1048576))
        target.write(chunk)
        now = time.monotonic()
        if now - last > 0.25:
            print("P %d %d" % (done, total), flush=True)
            last = now
    if total and done != total:
        raise SourceError("stream closed early (%d of %d bytes)" % (done, total))


class InvalidMedia(SourceError):
    pass


def save_media(source, *, dest, identity, title, meta, limit, total=0, mime="", kind="", url=""):
    """Validate the temporary file before it can replace any library item."""
    global _partial
    if total > limit:
        raise SourceError("file is %.1f MB, above the %d MB limit" % (total / 1048576, limit // 1048576))
    if mime and not (mime.startswith(("image/", "video/")) or mime in
                     ("application/octet-stream", "binary/octet-stream", "audio/webm")):
        raise InvalidMedia("server sent %s instead of media" % mime)

    os.makedirs(dest, exist_ok=True)
    base = safe_name(title) + "_" + safe_name(identity.replace(":", "-"))
    fd, _partial = tempfile.mkstemp(dir=dest, prefix=".media-", suffix=".part")
    try:
        with os.fdopen(fd, "wb") as f:
            stream_media(source, f, limit, total)
        info = media_info(_partial)
        if info.get("error"):
            raise InvalidMedia("file failed validation (%s)" % info["error"])
        advertised = ext_from(mime)
        if advertised and info["format"] != advertised and (advertised, info["format"]) != ("png", "apng"):
            raise InvalidMedia("file signature does not match %s" % mime)
        if kind in ("video", "animated") and info["kind"] != kind:
            raise InvalidMedia("file does not contain the expected %s" % kind)
        if kind == "image" and info["kind"] == "video":
            raise InvalidMedia("file is a video instead of an image")
        ext = info["format"]
        if ext == "webp" and info["kind"] == "animated":
            ext = "animated.webp"
        final = os.path.abspath(os.path.join(dest, base + "." + ext))
        os.chmod(_partial, 0o644)
        with state_lock(LIBRARY_FILE):
            os.replace(_partial, final)
            _partial = None
            lib = read_json(LIBRARY_FILE, {})
            lib[final] = {"id": identity, "url": url, "title": title, "kind": info["kind"], "format": info["format"],
                          "width": info["width"], "height": info["height"],
                          "downloaded": datetime.datetime.now().isoformat(timespec="seconds"),
                          **{key: meta.get(key, "") for key in (
                              "source", "sourceName", "pageUrl", "author", "license", "provenance", "provenanceReason")}}
            write_json_atomic(LIBRARY_FILE, lib, mode=0o600)
        info["path"] = final
        return {"ok": True, "path": final, "info": info}
    finally:
        if _partial and os.path.exists(_partial):
            os.remove(_partial)
        _partial = None


def cmd_download(a):
    signal.signal(signal.SIGTERM, _on_term)
    signal.signal(signal.SIGINT, _on_term)
    try:
        meta = json.loads(a.meta) if a.meta else {}
        if not isinstance(meta, dict):
            raise ValueError("invalid download metadata")
        with open_media(a.url, timeout=20, headers={"Accept": "image/*,video/*,application/octet-stream"}) as response:
            mime = (response.headers.get("Content-Type") or "").split(";", 1)[0].strip().lower()
            total = int(response.headers.get("Content-Length") or 0)
            result = save_media(response, dest=a.dest, identity=a.id, title=a.title, meta=meta,
                                limit=a.max_mb * 1048576, total=total, mime=mime, kind=a.kind, url=a.url)
        emit(result)
    except (OSError, ValueError, SourceError, http.client.HTTPException) as e:
        reason = getattr(e, "reason", None) or str(e)
        unavailable = isinstance(e, InvalidMedia) or getattr(e, "code", 0) in (401, 403, 404, 410)
        emit({"ok": False, "error": "download failed: %s" % reason, "unavailable": unavailable,
              "offline": isinstance(reason, socket.gaierror)})


def local_file_url(url):
    parts = urllib.parse.urlsplit(url)
    if parts.scheme != "file" or parts.netloc or parts.query or parts.fragment:
        raise SourceError("choose a local file")
    return urllib.request.url2pathname(parts.path)


def cmd_import(a):
    signal.signal(signal.SIGTERM, _on_term)
    signal.signal(signal.SIGINT, _on_term)
    items, errors = [], []
    for url in a.files:
        path = url
        try:
            path = local_file_url(url)
            if not os.path.isfile(path):
                raise SourceError("not a regular file")
            stat = os.stat(path)
            title = os.path.splitext(os.path.basename(path))[0]
            identity = "import:" + url_id(os.path.realpath(path) + ":%d:%d" % (stat.st_mtime_ns, stat.st_size))
            with open(path, "rb") as src:
                items.append(save_media(src, dest=a.dest, identity=identity, title=title,
                                        meta={"sourceName": "Local"}, limit=a.max_mb * 1048576, total=stat.st_size))
        except (ValueError, SourceError, OSError) as e:
            errors.append(os.path.basename(path) + ": " + str(e))
    emit({"ok": bool(items), "items": items, "errors": errors})


def cmd_prepare_animation(a):
    info = media_info(a.path)
    if info.get("error"):
        raise SourceError(info["error"])
    animated_webp = info["format"] == "webp" and info["kind"] == "animated" and not a.path.lower().endswith(".animated.webp")
    if info["format"] != "apng" and not animated_webp:
        if a.path.lower().endswith(".apng"):
            raise SourceError("the file has no APNG animation")
        emit({"ok": True, "path": a.path, "info": info})
        return
    # Qt Quick's PNG handler reads the still image. Reuse the existing Video
    # player and leave the downloaded APNG in the library.
    folder = os.path.join(STATE_DIR, "wallpaper_hub", "playback")
    ensure_private_dir(folder)
    st = os.stat(a.path)
    ext = ".animated.webp" if animated_webp else ".webm"
    converted = os.path.join(folder, url_id(a.path + ":%d:%d" % (st.st_mtime_ns, st.st_size)) + ext)
    if not os.path.isfile(converted):
        fd, tmp = tempfile.mkstemp(dir=folder, suffix=ext)
        os.close(fd)
        try:
            if animated_webp:
                shutil.copyfile(a.path, tmp)
            else:
                proc = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-protocol_whitelist", "file",
                                       "-i", a.path, "-an", "-c:v", "libvpx-vp9", "-crf", "26", "-b:v", "0",
                                       "-deadline", "good", "-pix_fmt", "yuva420p", tmp],
                                      text=True, capture_output=True, timeout=120)
                if proc.returncode or media_info(tmp).get("error"):
                    raise SourceError("could not convert APNG to WebM (requires ffmpeg with VP9)")
            os.chmod(tmp, 0o600)
            os.replace(tmp, converted)
        finally:
            if os.path.exists(tmp):
                os.remove(tmp)
    emit({"ok": True, "path": converted, "info": info})


# --------------------------------------------------------------------------- quality / editing


def gray_crop(path, w, h, seek=None):
    """Native-resolution grayscale centre crop (no rescaling, so real detail is kept)."""
    cw, ch = min(w, 1024), min(h, 768)
    cw -= cw % 8
    ch -= ch % 8
    x, y = (w - cw) // 2, (h - ch) // 2
    x -= x % 8  # keep the JPEG 8x8 grid aligned for the blockiness test
    y -= y % 8
    cmd = ["ffmpeg", "-v", "error"]
    if seek:
        cmd += ["-ss", "%.2f" % seek]
    cmd += ["-i", path, "-frames:v", "1", "-vf", "crop=%d:%d:%d:%d,format=gray" % (cw, ch, x, y), "-f", "rawvideo", "-"]
    r = subprocess.run(cmd, capture_output=True, timeout=60)
    if r.returncode != 0 or len(r.stdout) < cw * ch:
        raise RuntimeError((r.stderr.decode("utf-8", "replace").strip().splitlines() or ["ffmpeg failed"])[-1])
    return r.stdout[:cw * ch], cw, ch


def analyse_pixels(px, w, h):
    """Several independent detail measurements on a grayscale crop."""
    n = w * h
    grad = [0] * n
    for y in range(h - 1):
        row = y * w
        for x in range(w - 1):
            i = row + x
            v = px[i]
            grad[i] = abs(v - px[i + 1]) + abs(v - px[i + w])
    tex = [i for i in range(n) if grad[i] > 14 and (i % w) < w - 2 and i // w < h - 2]
    tex_frac = len(tex) / float(n)

    # 2x and 4x down/up round trip: real fine detail is lost, enlarged content survives.
    def roundtrip(f):
        sw, sh = w // f, h // f
        small = [0.0] * (sw * sh)
        inv = 1.0 / (f * f)
        for sy in range(sh):
            for sx in range(sw):
                acc = 0
                for dy in range(f):
                    base = (sy * f + dy) * w + sx * f
                    for dx in range(f):
                        acc += px[base + dx]
                small[sy * sw + sx] = acc * inv
        res, cnt = 0.0, 0
        for i in tex:
            x, y = i % w, i // w
            fx = (x + 0.5) / f - 0.5
            fy = (y + 0.5) / f - 0.5
            x0 = min(max(int(fx), 0), sw - 2)
            y0 = min(max(int(fy), 0), sh - 2)
            ax = min(max(fx - x0, 0.0), 1.0)
            ay = min(max(fy - y0, 0.0), 1.0)
            s0 = small[y0 * sw + x0] * (1 - ax) + small[y0 * sw + x0 + 1] * ax
            s1 = small[(y0 + 1) * sw + x0] * (1 - ax) + small[(y0 + 1) * sw + x0 + 1] * ax
            res += abs(px[i] - (s0 * (1 - ay) + s1 * ay))
            cnt += 1
        return res / cnt if cnt else 0.0

    mean_grad = (sum(grad[i] for i in tex) / len(tex)) if tex else 0.0
    r2 = roundtrip(2) if len(tex) > 200 else 0.0
    r4 = roundtrip(4) if len(tex) > 200 else 0.0

    # Blockiness along column boundaries for several periods (8 = native JPEG,
    # 12/16/24/32 = JPEG blocks that were enlarged 1.5x/2x/3x/4x).
    def block_ratio(period):
        on = off = 0.0
        con = coff = 0
        for y in range(0, h, 2):
            row = y * w
            for x in range(1, w):
                d = abs(px[row + x] - px[row + x - 1])
                if d > 40:
                    continue  # ignore real edges
                if x % period == 0:
                    on += d
                    con += 1
                else:
                    off += d
                    coff += 1
        return (on / con) / (off / coff) if con and coff and off > 0 else 1.0

    blocks = {p: round(block_ratio(p), 3) for p in (8, 12, 16, 24, 32)}
    flat = [grad[i] for i in range(0, n, 3) if grad[i] <= 4]
    noise = sum(flat) / len(flat) if flat else 0.0
    return {"textureFraction": round(tex_frac, 4), "meanEdge": round(mean_grad, 2),
            "detailHalf": round(r2 / mean_grad, 4) if mean_grad else 0.0,
            "detailQuarter": round(r4 / mean_grad, 4) if mean_grad else 0.0,
            "blockiness": blocks, "flatNoise": round(noise, 3)}


UPSCALER_MARKERS = (b"waifu2x", b"real-esrgan", b"realesrgan", b"esrgan", b"topaz gigapixel", b"gigapixel", b"upscayl",
                    b"chainner", b"letsenhance", b"bigjpg")
CAMERA_MAKERS = (b"nikon", b"canon", b"sony", b"fujifilm", b"olympus", b"panasonic", b"pentax", b"leica", b"hasselblad")


def scan_metadata(path):
    found, camera, software = [], False, ""
    try:
        with open(path, "rb") as f:
            head = f.read(256 * 1024)
    except OSError:
        return found, camera, software
    low = head.lower()
    for m in UPSCALER_MARKERS:
        if m in low:
            found.append(m.decode())
    camera = b"exif\x00\x00" in low and any(m in low for m in CAMERA_MAKERS)
    m = re.search(rb"(?:Software|CreatorTool)[^\x20-\x7e]{0,8}([\x20-\x7e]{3,60})", head)
    if m:
        software = m.group(1).decode("ascii", "replace").strip()
    return found, camera, software


# Thresholds calibrated on real Wallhaven 3840x2160 originals versus the same
# pictures shrunk to 1440p/1080p/720p and enlarged back with bicubic/Lanczos:
#   finest-octave share (detailHalf / detailQuarter)
#     native 0.62-0.81 | 1.5x 0.50-0.53 | 2x 0.39-0.42 | 3x 0.35-0.36
#   detailHalf: native >= 0.29 | 1.5x 0.25-0.28 | 2x 0.19-0.22 | 3x 0.17
# A uniform blur lowers both octaves (detailQuarter < 0.35), resampling keeps
# the coarse octave (detailQuarter 0.46-0.52); that separates soft art from upscales.
OCTAVE_UPSCALE = 0.47
OCTAVE_MILD = 0.57
HALF_SOFT = 0.24
QUARTER_BLUR = 0.35


def judge(info, px, meta, provenance, provenance_reason):
    reasons, signals = [], []
    w, h = info["width"], info["height"]
    bpp = info["size"] * 8.0 / (w * h) if w and h else 0
    if info["kind"] == "video" and info.get("fps"):
        bpp = info.get("bitrate", 0) / (w * h * info["fps"]) if w and h else 0
    markers, camera, software = meta
    if markers:
        signals.append("metadata")
        reasons.append("File metadata names an upscaling tool: " + ", ".join(sorted(set(markers))) + ".")
    if camera:
        reasons.append("Camera EXIF data present (typical of an original photo export).")
    if software:
        reasons.append("Software recorded in metadata: " + software + ".")
    verdict = "ok"
    if px is None:
        verdict = "inconclusive"
        reasons.append("Pixel analysis unavailable.")
    else:
        tf, dh, dq = px["textureFraction"], px["detailHalf"], px["detailQuarter"]
        b = px["blockiness"]
        if tf < 0.02:
            verdict = "inconclusive"
            reasons.append("Mostly smooth or minimal content (%.1f%% textured pixels): a detail test cannot tell an intentional "
                           "soft or minimal picture from an upscale, so it is not penalised." % (tf * 100))
        elif dq and dq < QUARTER_BLUR:
            verdict = "inconclusive"
            reasons.append("Detail is low at every scale (2x %.3f, 4x %.3f): this looks like an intentional blur or soft style, "
                           "which a detail test cannot separate from an upscale, so it is not penalised." % (dh, dq))
        else:
            share = dh / dq if dq else 1.0
            if share < OCTAVE_UPSCALE:
                signals.append("octave")
                reasons.append("Only %.0f%% of the detail sits in the finest pixel scale (native files measured 62-81%%): "
                               "typical of content enlarged about 2x or more." % (share * 100))
            elif share < OCTAVE_MILD:
                signals.append("octave-mild")
                reasons.append("Finest pixel scale holds %.0f%% of the detail (native files 62-81%%): slightly soft, "
                               "consistent with a ~1.5x enlargement or light smoothing." % (share * 100))
            else:
                reasons.append("Finest pixel scale holds %.0f%% of the detail: real full-resolution detail." % (share * 100))
            if dh < HALF_SOFT:
                signals.append("soft")
                reasons.append("Fine detail survives a 2x downscale almost unchanged (residual %.3f; native files measured 0.29 or more)." % dh)
            b8 = b.get(8, 1) or 1
            enlarged = [p for p in (16, 24, 32) if b.get(p, 1) > 1.2 and b.get(p, 1) / b8 > 1.08]
            if enlarged:
                signals.append("blockgrid")
                reasons.append("Compression blocks repeat every %d px instead of 8 px: an already compressed image was enlarged." % enlarged[0])
            if b8 > 1.35:
                reasons.append("Visible JPEG 8x8 blocking (ratio %.2f): strong compression." % b8)
            if px["flatNoise"] < 0.15 and signals:
                reasons.append("Flat areas are perfectly clean (no grain); on its own this is normal for digital art.")
    if info["kind"] == "video" and bpp:
        if bpp < 0.015:
            signals.append("lowbitrate")
            reasons.append("Very low bitrate for this resolution (%.3f bits per pixel per frame): compression hides detail." % bpp)
        elif bpp < 0.03:
            reasons.append("Low bitrate for this resolution (%.3f bits per pixel per frame)." % bpp)
        else:
            reasons.append("Bitrate %.3f bits per pixel per frame." % bpp)
    elif bpp:
        reasons.append("%.2f bits per pixel in the file." % bpp)
    if "metadata" in signals or len(signals) >= 2:
        verdict = "upscale"
    elif signals and verdict != "inconclusive":
        verdict = "lowdetail"
    labels = {"upscale": "Possible Upscale", "lowdetail": "Low Detail", "ok": "Detail OK", "inconclusive": "Inconclusive"}
    return {
        "verdict": verdict, "label": labels[verdict], "signals": signals,
        "provenance": provenance, "provenanceLabel": "Verified Source" if provenance == "verified" else "Source Unknown",
        "provenanceReason": provenance_reason or ("No reliable origin data." if provenance != "verified" else ""),
        "reasons": reasons, "metrics": px or {}, "bitsPerPixel": round(bpp, 4),
        "note": "A single file cannot prove it is a native high-resolution original; this is an estimate from several measurements.",
    }


def cmd_quality(a):
    info = media_info(a.path)
    if info.get("error"):
        emit({"ok": False, "error": info["error"], "info": info})
        return
    px, err = None, None
    if shutil.which("ffmpeg"):
        try:
            seek = info["duration"] * 0.3 if info["kind"] == "video" and info.get("duration") else None
            raw, cw, ch = gray_crop(a.path, info["width"], info["height"], seek)
            px = analyse_pixels(raw, cw, ch)
        except Exception as e:  # analysis is optional
            err = str(e)
    else:
        err = "ffmpeg is not installed"
    entry = read_json(LIBRARY_FILE, {}).get(a.path, {})
    prov = a.provenance or entry.get("provenance") or "unknown"
    reason = a.provenance_reason or entry.get("provenanceReason") or ""
    q = judge(info, px, scan_metadata(a.path), prov, reason)
    if err:
        q["reasons"].append("Pixel analysis failed: " + err)
    if a.id:
        qc = read_json(QUALITY_CACHE, {})
        qc[a.id] = {"verdict": q["verdict"], "label": q["label"], "provenanceLabel": q["provenanceLabel"]}
        write_json_atomic(QUALITY_CACHE, qc)
    emit({"ok": True, "info": info, "quality": q})


# --------------------------------------------------------------------------- studio

_tool_cache = {}


def ffmpeg_list(kind):
    if kind not in _tool_cache:
        try:
            r = subprocess.run(["ffmpeg", "-hide_banner", "-" + kind], capture_output=True, text=True, timeout=15)
            _tool_cache[kind] = r.stdout
        except Exception:
            _tool_cache[kind] = ""
    return _tool_cache[kind]


def has_filter(name):
    return re.search(r"\s" + re.escape(name) + r"\s", ffmpeg_list("filters")) is not None


def has_encoder(name):
    return re.search(r"\s" + re.escape(name) + r"\s", ffmpeg_list("encoders")) is not None


def build_filters(p, info):
    f = []
    W, H = info["width"], info["height"]
    zoom = max(1.0, min(4.0, float(p.get("zoom", 1.0))))
    cx = max(0.0, min(0.95, float(p.get("cropX", 0))))
    cy = max(0.0, min(0.95, float(p.get("cropY", 0))))
    cw = max(0.05, min(float(p.get("cropW", 1)), 1 - cx))
    ch = max(0.05, min(float(p.get("cropH", 1)), 1 - cy))
    rw, rh = cw / zoom, ch / zoom
    posx = max(0.0, min(1.0, float(p.get("posX", 0.5))))
    posy = max(0.0, min(1.0, float(p.get("posY", 0.5))))
    x0, y0 = cx + (cw - rw) * posx, cy + (ch - rh) * posy
    if zoom > 1.0 or cw < 1 or ch < 1:
        w_, h_ = max(16, int(W * rw) // 2 * 2), max(16, int(H * rh) // 2 * 2)
        f.append("crop=%d:%d:%d:%d" % (w_, h_, int(W * x0), int(H * y0)))
        if zoom > 1.0:
            # Zoom keeps the original pixel size; the result is an enlargement and is labelled as such.
            f.append("scale=%d:%d:flags=lanczos" % (int(w_ * zoom) // 2 * 2, int(h_ * zoom) // 2 * 2))
    br = max(-1.0, min(1.0, float(p.get("brightness", 0))))
    co = max(0.2, min(3.0, float(p.get("contrast", 1))))
    sa = max(0.0, min(3.0, float(p.get("saturation", 1))))
    if br or co != 1 or sa != 1:
        f.append("eq=brightness=%.3f:contrast=%.3f:saturation=%.3f" % (br * 0.5, co, sa))
    temp = int(p.get("temperature", 6500))
    if temp != 6500:
        if has_filter("colortemperature"):
            f.append("colortemperature=temperature=%d" % max(1000, min(40000, temp)))
        else:
            k = (6500 - temp) / 5500.0
            f.append("colorbalance=rm=%.3f:bm=%.3f" % (k * 0.3, -k * 0.3))
    blur = max(0.0, min(40.0, float(p.get("blur", 0))))
    if blur > 0:
        f.append("gblur=sigma=%.2f" % blur)
    return f


def strip_ext(path):
    return re.sub(r"\.[A-Za-z0-9]+$", "", path)


def cmd_edit(a):
    try:
        p = json.loads(a.params or "{}")
    except ValueError:
        emit({"ok": False, "error": "bad edit parameters"})
        return
    info = media_info(a.input)
    if info.get("error"):
        emit({"ok": False, "error": info["error"]})
        return
    if not shutil.which("ffmpeg"):
        emit({"ok": False, "error": "ffmpeg is not installed"})
        return
    motion = info["kind"] in ("video", "animated")
    vf = build_filters(p, info)
    preview = a.preview
    os.makedirs(os.path.dirname(a.output), exist_ok=True)
    cmd = ["ffmpeg", "-y", "-hide_banner", "-v", "error"]
    if not motion:
        if preview:
            vf.append("scale='min(1280,iw)':-2")
        ext = "jpg" if info["format"] == "jpg" else "png"
        out = strip_ext(a.output) + "." + ext
        cmd += ["-i", a.input, "-frames:v", "1"]
        if vf:
            cmd += ["-vf", ",".join(vf)]
        cmd += (["-q:v", "2"] if ext == "jpg" else []) + ["-update", "1", out]
    else:
        start = max(0.0, float(p.get("trimStart", 0)))
        end = float(p.get("trimEnd", 0))
        dur = float(info.get("duration") or 0)
        if end <= 0 or (dur > 0 and end > dur):
            end = dur
        speed = max(0.25, min(4.0, float(p.get("speed", 1))))
        loop = p.get("loop", "none")
        if speed != 1:
            vf.append("setpts=PTS/%.4f" % speed)
        if preview:
            vf.append("scale='min(960,iw)':-2")
            if end <= start or end - start > 6:
                end = start + 6
        seg = end - start if end > start else 0
        if loop == "pingpong" and (seg > 30 or (seg == 0 and dur > 30)):
            emit({"ok": False, "error": "ping-pong loop is limited to clips of 30 s or less; trim the clip first"})
            return
        if start > 0:
            cmd += ["-ss", "%.3f" % start]
        if seg > 0:
            cmd += ["-t", "%.3f" % seg]
        cmd += ["-i", a.input]
        chain = (",".join(vf) + ",") if vf else ""
        if info["kind"] == "animated":
            out = strip_ext(a.output) + ".gif"
            if loop == "pingpong":
                graph = "[0:v]%ssplit[a][b];[b]reverse[r];[a][r]concat=n=2:v=1,split[x][y];[x]palettegen[pal];[y][pal]paletteuse" % chain
            else:
                graph = "[0:v]%ssplit[x][y];[x]palettegen[pal];[y][pal]paletteuse" % chain
            cmd += ["-filter_complex", graph, "-loop", "0", out]
        else:
            if has_encoder("libx264"):
                codec, ext, extra = "libx264", "mp4", ["-crf", "28" if preview else "18", "-preset", "veryfast" if preview else "medium", "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
            elif has_encoder("libvpx-vp9"):
                codec, ext, extra = "libvpx-vp9", "webm", ["-crf", "34" if preview else "28", "-b:v", "0", "-deadline", "realtime" if preview else "good", "-row-mt", "1"]
            elif has_encoder("libopenh264"):
                codec, ext, extra = "libopenh264", "mp4", ["-b:v", str(max(int(info.get("bitrate") or 0), 4000000)), "-pix_fmt", "yuv420p"]
            else:
                codec, ext, extra = "mpeg4", "mp4", ["-q:v", "3"]
            out = strip_ext(a.output) + "." + ext
            if loop == "pingpong":
                cmd += ["-filter_complex", "[0:v]%ssplit[a][b];[b]reverse[r];[a][r]concat=n=2:v=1[o]" % chain, "-map", "[o]"]
            elif vf:
                cmd += ["-vf", ",".join(vf)]
            cmd += ["-an", "-c:v", codec] + extra + [out]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
    except subprocess.TimeoutExpired:
        emit({"ok": False, "error": "render took longer than 30 minutes and was stopped"})
        return
    if r.returncode != 0 or not os.path.exists(out):
        emit({"ok": False, "error": (r.stderr.strip().splitlines() or ["ffmpeg failed"])[-1]})
        return
    os.chmod(out, 0o644)
    res = media_info(out)
    if not preview:
        with state_lock(LIBRARY_FILE):
            lib = read_json(LIBRARY_FILE, {})
            src = dict(lib.get(a.input, {}))
            src.update({"editedFrom": a.input, "edit": p, "downloaded": datetime.datetime.now().isoformat(timespec="seconds"),
                        "title": (src.get("title") or os.path.basename(a.input)) + " (edited)", "kind": res["kind"], "format": res["format"]})
            lib[out] = src
            write_json_atomic(LIBRARY_FILE, lib, mode=0o600)
    emit({"ok": True, "path": out, "info": res, "preview": preview})


# --------------------------------------------------------------------------- library / keys / status

def local_items(dirs, query="", kind="all"):
    # One entry per real file: the wallpaper folder contains the download folder, and
    # symlinks or mixed separators must not list the same wallpaper twice.
    def key(p):
        return os.path.normcase(os.path.realpath(p))
    lib = {key(k): v for k, v in read_json(LIBRARY_FILE, {}).items()}
    items, seen = [], set()
    for d in [d for d in dirs if d]:
        if not os.path.isdir(d):
            continue
        for root, sub, files in os.walk(d):
            sub[:] = [s for s in sub if not s.startswith(".")]
            if root[len(d):].count(os.sep) >= 2:
                sub[:] = []
            for fn in files:
                ext = fn.rsplit(".", 1)[-1].lower() if "." in fn else ""
                ext = "jpg" if ext == "jpeg" else ext
                if ext not in MEDIA_EXT or fn.startswith("."):
                    continue
                path = os.path.abspath(os.path.join(root, fn))
                if key(path) in seen:
                    continue
                seen.add(key(path))
                try:
                    st = os.stat(path)
                except OSError:
                    continue
                m = lib.get(key(path), {})
                media_kind = m.get("kind") or ("animated" if fn.lower().endswith(".animated.webp") else kind_of(ext))
                if not m.get("kind") and ext in ("webp", "png"):
                    try:
                        with open(path, "rb") as file:
                            if animation_frames(file, ext) > 1:
                                media_kind = "animated"
                                if ext == "png":
                                    ext = "apng"
                    except OSError:
                        pass
                title = m.get("title", "") or fn
                if (kind != "all" and media_kind != kind) or (query and not matches_query(title + " " + fn, query)):
                    continue
                items.append({"path": path, "name": fn, "format": m.get("format") or ext, "kind": media_kind, "size": st.st_size,
                              "pageUrl": m.get("pageUrl", ""), "width": m.get("width", 0), "height": m.get("height", 0),
                              "mtime": int(st.st_mtime), "source": m.get("sourceName", ""), "title": m.get("title", "") or fn,
                              "edited": bool(m.get("editedFrom")), "hub": bool(m),
                              "provenance": m.get("provenance", ""), "provenanceReason": m.get("provenanceReason", ""), "id": m.get("id", "")})
    items.sort(key=lambda x: (not x["hub"], -x["mtime"]))
    return items


def cmd_local(a):
    dirs = a.dirs.split("|") + getattr(a, "dir", []) + load_custom_sources()["folders"]
    emit({"ok": True, "items": local_items(dirs)[:400]})


def cmd_custom_sources(a):
    if not a.action:
        emit({"ok": True, "sources": load_custom_sources()})
        return
    value = sys.stdin.readline().strip()
    if a.action == "add":
        if a.field == "folders":
            value = local_file_url(value)
            if not os.path.isdir(value):
                raise SourceError("the chosen local folder does not exist")
        elif not web_url(value):
            raise SourceError("enter a public HTTP(S) URL")
    with state_lock(SOURCES_FILE):
        sources = load_custom_sources()
        entries = sources[a.field]
        if a.action == "remove":
            sources[a.field] = [x for x in entries if x != value]
        elif value not in entries:
            if len(entries) >= 12:
                raise SourceError("up to 12 entries per source type")
            entries.append(value)
        write_json_atomic(SOURCES_FILE, sources, mode=0o600)
    emit({"ok": True, "sources": sources})


def cmd_check_source(a):
    keys = load_keys()
    if CAPS[a.source]["key"] == "required" and not keys.get(a.source):
        return emit({"ok": False, "error": "API key required"})
    c = Ctx(q="nature", page=1, kind="all", minres=RES["any"], keys=keys, safe=True, lang="en",
            sort="relevance", urls=load_custom_sources()["urls"], dirs=[])
    if a.source == "brave":
        src_general_images(c)
        src_general_videos(c)
    elif a.source == "links":
        if not c.urls:
            return emit({"ok": False, "error": "add a URL or feed first"})
        for url in c.urls:
            if ext_from(url=url):
                with open_media(url, timeout=6, headers={"Range": "bytes=0-63"}) as response:
                    if not sniff(response.read(64)):
                        raise SourceError("a direct URL did not return supported media")
            else:
                # Advance once to trigger HTTP and parse even if the feed is empty.
                next(feed_entries(url), None)
    else:
        if a.source in ("sepia", "steam"):
            c.kind = "video"
        SOURCE_FUNCS[a.source](c)
    emit({"ok": True})


def cmd_keys(a):
    keys = load_keys()
    emit({"ok": True, "keys": {k: bool(keys.get(k)) for k in KEY_SOURCES}})


def cmd_favorites(a):
    if not a.update:
        emit({"ok": True, "items": read_json(FAVORITES_FILE, {})})
        return
    entry = json.loads(sys.stdin.readline())
    identity = entry.get("id")
    if not isinstance(identity, str) or not identity or len(identity) > 4096:
        raise SourceError("invalid favorite identity")
    with state_lock(FAVORITES_FILE):
        items = read_json(FAVORITES_FILE, {})
        if entry.get("remove"):
            items.pop(identity, None)
        else:
            items[identity] = {
                "id": identity, "title": str(entry.get("title") or "")[:240], "sourceName": str(entry.get("sourceName") or "")[:120],
                "collection": str(entry.get("collection") or "").strip()[:60],
                "path": entry.get("path") or "", "pageUrl": web_url(entry.get("pageUrl")),
                "kind": entry.get("kind") or "image", "format": entry.get("format") or "",
            }
        write_json_atomic(FAVORITES_FILE, items, mode=0o600)
    emit({"ok": True, "items": items})


def cmd_set_key(a):
    if a.source not in KEY_SOURCES:
        emit({"ok": False, "error": "unknown source"})
        return
    value = sys.stdin.readline().strip()
    if value and not re.fullmatch(r"[A-Za-z0-9_\-]{8,128}", value):
        emit({"ok": False, "error": "this does not look like an API key"})
        return
    ensure_private_dir(os.path.dirname(SECRETS_FILE))
    data = read_json(SECRETS_FILE, {})
    if not isinstance(data, dict):
        data = {}
    if value:
        data[a.source] = value
    else:
        data.pop(a.source, None)
    write_json_atomic(SECRETS_FILE, data, mode=0o600)
    emit({"ok": True, "source": a.source, "set": bool(value)})


def cmd_history(a):
    items = [q for q in read_json(HISTORY_FILE, []) if isinstance(q, str)]
    if a.clear:
        items = []
    elif a.remove:
        items = [q for q in items if q != a.remove]
    if a.clear or a.remove:
        ensure_private_dir(HUB_STATE)
        write_json_atomic(HISTORY_FILE, items, mode=0o600)
    emit({"ok": True, "items": items[:HISTORY_MAX]})


def cmd_status(a):
    online, detail = False, ""
    for host in ("wallhaven.cc", "commons.wikimedia.org"):
        try:
            with socket.create_connection((host, 443), timeout=3):
                online = True
                break
        except OSError as e:
            detail = "%s: %s" % (host, e)
    keys = load_keys()
    emit({"ok": True, "online": online, "detail": "" if online else detail,
          "ffmpeg": bool(shutil.which("ffmpeg")), "ffprobe": bool(shutil.which("ffprobe")),
          "keys": {k: bool(keys.get(k)) for k in KEY_SOURCES}, "caps": CAPS})


def main():
    ap = argparse.ArgumentParser(description="Serpantinum Wallpaper Hub backend")
    sp = ap.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("search")
    s.add_argument("--query", required=True)
    s.add_argument("--page", type=int, default=1)
    s.add_argument("--kind", choices=["all", "image", "animated", "video"], default="all")
    s.add_argument("--min", default="any", choices=list(RES))
    s.add_argument("--translate", choices=["auto", "off"], default="auto")
    s.add_argument("--sources")
    s.add_argument("--source-pages", default="")
    s.add_argument("--dir", action="append", default=[])
    s.add_argument("--include-unknown", action="store_true", help="include media without reported dimensions")
    s.add_argument("--sort", default="relevance", choices=list(SORTS))
    s.add_argument("--unsafe", dest="safe", action="store_false")
    s.add_argument("--remember", action="store_true", help="add the query to the local search history")
    s.set_defaults(func=cmd_search)
    s = sp.add_parser("cache-thumbs")
    s.set_defaults(func=cmd_cache_thumbs)
    s = sp.add_parser("probe")
    s.add_argument("path")
    s.set_defaults(func=cmd_probe)
    s = sp.add_parser("download")
    s.add_argument("--url", required=True)
    s.add_argument("--id", required=True)
    s.add_argument("--title", default="")
    s.add_argument("--dest", required=True)
    s.add_argument("--max-mb", type=int, default=400)
    s.add_argument("--meta", default="")
    s.add_argument("--kind", choices=["", "image", "animated", "video"], default="")
    s.set_defaults(func=cmd_download)
    s = sp.add_parser("import")
    s.add_argument("--dest", required=True)
    s.add_argument("--max-mb", type=int, default=400)
    s.add_argument("files", nargs="+")
    s.set_defaults(func=cmd_import)
    s = sp.add_parser("prepare-animation")
    s.add_argument("path")
    s.set_defaults(func=cmd_prepare_animation)
    s = sp.add_parser("quality")
    s.add_argument("path")
    s.add_argument("--id", default="")
    s.add_argument("--provenance", default="")
    s.add_argument("--provenance-reason", default="")
    s.set_defaults(func=cmd_quality)
    s = sp.add_parser("edit")
    s.add_argument("--input", required=True)
    s.add_argument("--output", required=True)
    s.add_argument("--params", default="{}")
    s.add_argument("--preview", action="store_true")
    s.set_defaults(func=cmd_edit)
    s = sp.add_parser("local")
    s.add_argument("--dirs", default="")
    s.add_argument("--dir", action="append", default=[])
    s.set_defaults(func=cmd_local)
    s = sp.add_parser("keys")
    s.set_defaults(func=cmd_keys)
    s = sp.add_parser("favorites")
    s.add_argument("--update", action="store_true")
    s.set_defaults(func=cmd_favorites)
    s = sp.add_parser("set-key")
    s.add_argument("source")
    s.set_defaults(func=cmd_set_key)
    s = sp.add_parser("status")
    s.set_defaults(func=cmd_status)
    s = sp.add_parser("check-source")
    s.add_argument("source", choices=[name for name in CAPS if name != "local"])
    s.set_defaults(func=cmd_check_source)
    s = sp.add_parser("resolve-peertube")
    s.add_argument("--page-url", required=True)
    s.add_argument("--uuid", required=True)
    s.add_argument("--unsafe", dest="safe", action="store_false")
    s.set_defaults(func=cmd_peertube)
    s = sp.add_parser("custom-sources")
    s.add_argument("action", nargs="?", choices=["add", "remove"])
    s.add_argument("field", nargs="?", choices=["folders", "urls"])
    s.set_defaults(func=cmd_custom_sources)
    s = sp.add_parser("history")
    s.add_argument("--clear", action="store_true")
    s.add_argument("--remove", default="")
    s.set_defaults(func=cmd_history)
    a = ap.parse_args()
    try:
        a.func(a)
    except Exception as e:  # always answer with JSON so the UI never hangs
        emit({"event": "done", "ok": False, "error": "%s: %s" % (type(e).__name__, e)})


if __name__ == "__main__":
    main()
