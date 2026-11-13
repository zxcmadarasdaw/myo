#!/usr/bin/env python3
"""Wallpaper Hub backend for Serpantinum.

Real internet search through official, documented APIs only:
  * Wallhaven      https://wallhaven.cc/help/api            (no key needed for SFW)
  * Wikimedia Commons MediaWiki API                         (no key)
  * Openverse      https://api.openverse.org/v1/            (no key, rate limited)
  * Pexels         https://www.pexels.com/api/              (user API key)
  * Pixabay        https://pixabay.com/api/docs/            (user API key)
  * Giphy          https://developers.giphy.com/            (user API key)

Optional query translation (ru -> en) uses the public MyMemory API and is
reported back so the UI can show what was actually sent. Nothing here executes
downloaded content: files are streamed to disk, size-capped, identified by
their magic bytes, decoded with ffprobe and stored mode 0644.

Every command prints exactly one JSON object on stdout as its last line
(download also prints "P <done> <total>" progress lines before it).
"""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

VERSION = "1.0"
UA = "SerpantinumWallpaperHub/" + VERSION + " (+https://serpantinum.dev; desktop wallpaper search client)"
HOME = os.path.expanduser("~")
CONFIG_DIR = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
STATE_DIR = os.environ.get("QS_STATE_DIR") or os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local/state"), "serpantinum")
CACHE_DIR = os.environ.get("QS_CACHE_DIR") or os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"), "serpantinum")
# API keys live outside settings.json, which Themess can export and share.
SECRETS_FILE = os.path.join(CONFIG_DIR, "serpantinum", "secrets", "wallpaper_hub.json")
HUB_STATE = os.path.join(STATE_DIR, "wallpaper_hub")
LIBRARY_FILE = os.path.join(HUB_STATE, "library.json")
QUALITY_CACHE = os.path.join(HUB_STATE, "quality.json")
THUMB_DIR = os.path.join(CACHE_DIR, "wallpaper_hub", "thumbs")

TIMEOUT = 12
PER_PAGE = 24
KEY_SOURCES = ("pexels", "pixabay", "giphy", "wallhaven")
ALL_SOURCES = ("wallhaven", "commons", "openverse", "pexels", "pixabay", "giphy")
RES = {"any": (0, 0), "1080p": (1920, 1080), "1440p": (2560, 1440), "4k": (3840, 2160), "8k": (7680, 4320)}
MEDIA_EXT = {"jpg", "png", "webp", "gif", "mp4", "webm"}


class SourceError(Exception):
    pass


class Offline(Exception):
    pass


def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
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
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def load_keys():
    data = read_json(SECRETS_FILE, {})
    if not isinstance(data, dict):
        return {}
    return {k: str(v) for k, v in data.items() if k in KEY_SOURCES and v}


# --------------------------------------------------------------------------- HTTP

def http_get(url, headers=None, timeout=TIMEOUT, want_json=True):
    h = {"User-Agent": UA, "Accept": "application/json" if want_json else "*/*"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, headers=h)
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
        raise SourceError("HTTP %d %s%s" % (e.code, e.reason or "", (": " + detail) if detail else ""))
    except urllib.error.URLError as e:
        reason = e.reason
        if isinstance(reason, (socket.timeout, TimeoutError)):
            raise SourceError("timed out after %ds" % timeout)
        if isinstance(reason, (socket.gaierror, ConnectionRefusedError, ConnectionResetError, OSError)):
            raise Offline(str(reason))
        raise SourceError(str(reason))
    except (socket.timeout, TimeoutError):
        raise SourceError("timed out after %ds" % timeout)
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
    m = (mime or "").lower()
    table = {"image/jpeg": "jpg", "image/jpg": "jpg", "image/png": "png", "image/webp": "webp",
             "image/gif": "gif", "video/mp4": "mp4", "video/webm": "webm"}
    if m in table:
        return table[m]
    path = urllib.parse.urlparse(url or "").path.lower()
    e = path.rsplit(".", 1)[-1] if "." in path else ""
    e = "jpg" if e == "jpeg" else e
    return e if e in MEDIA_EXT else ""


def kind_of(fmt):
    if fmt in ("mp4", "webm"):
        return "video"
    if fmt == "gif":
        return "animated"
    return "image"


def item(**kw):
    base = {
        "id": "", "source": "", "sourceName": "", "title": "", "pageUrl": "", "thumb": "", "preview": "",
        "url": "", "width": 0, "height": 0, "format": "", "kind": "", "size": 0, "fps": 0,
        "duration": 0, "codec": "", "bitrate": 0, "author": "", "license": "", "sourceLink": "",
        "provenance": "unknown", "provenanceReason": "", "notes": [], "originalAvailable": True,
    }
    base.update(kw)
    if not base["kind"]:
        base["kind"] = kind_of(base["format"])
    if base["kind"] == "animated":
        base["notes"] = list(base["notes"]) + ["GIF: animation is confirmed only after download (frame count check)."]
    if base["kind"] == "video" and base["duration"] and base["size"] and not base["bitrate"]:
        base["bitrate"] = int(base["size"] * 8 / base["duration"])
        base["bitrateEstimated"] = True
    base["qualityKnown"] = bool(base["width"] and base["height"] and base["size"])
    return base


def strip_html(s):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", s or "")).strip()


# --------------------------------------------------------------------------- sources

def src_wallhaven(q, page, kind, minres, keys, safe):
    if kind in ("animated", "video"):
        return [], False, "Wallhaven hosts still images only"
    params = {"q": q, "page": page, "sorting": "relevance", "categories": "111", "purity": "100"}
    if minres[0]:
        params["atleast"] = "%dx%d" % minres
    if keys.get("wallhaven"):
        params["apikey"] = keys["wallhaven"]
        if not safe:
            params["purity"] = "110"
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
            provenance="unknown",
            provenanceReason=("Uploader cites an origin (" + src + "), but Wallhaven does not verify it." if src
                              else "Community upload without a stated origin."),
            sourceLink=src))
    meta = d.get("meta") or {}
    return out, int(meta.get("current_page") or page) < int(meta.get("last_page") or 0), None


def src_commons(q, page, kind, minres, keys, safe):
    terms = [q]
    if kind == "video":
        terms.append("filetype:video")
    elif kind == "animated":
        terms.append("filemime:image/gif")
    elif kind == "image":
        terms.append("filetype:bitmap")
    else:
        terms.append("filetype:bitmap|video")
    if minres[0]:
        terms += ["filew:>%d" % (minres[0] - 1), "fileh:>%d" % (minres[1] - 1)]
    params = {
        "action": "query", "format": "json", "generator": "search", "gsrnamespace": "6",
        "gsrsearch": " ".join(terms), "gsrlimit": PER_PAGE, "gsroffset": (page - 1) * PER_PAGE,
        "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata", "iiurlwidth": "480",
        "iiextmetadatafilter": "Artist|LicenseShortName|Credit|ObjectName",
    }
    d = http_get("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params))
    if d.get("error"):
        raise SourceError(str(d["error"].get("info") or d["error"]))
    pages = sorted(((d.get("query") or {}).get("pages") or {}).values(), key=lambda p: p.get("index", 0))
    out = []
    for p in pages:
        ii = (p.get("imageinfo") or [{}])[0]
        fmt = ext_from(ii.get("mime"), ii.get("url"))
        if fmt not in MEDIA_EXT:
            continue  # ogv, tiff, svg ... are not supported by the wallpaper engine
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
            preview=ii.get("url", "") if fmt in ("gif", "mp4", "webm") else thumb,
            url=ii.get("url", ""), width=int(ii.get("width") or 0), height=int(ii.get("height") or 0),
            format=fmt, size=int(ii.get("size") or 0), duration=float(ii.get("duration") or 0),
            author=val("Artist"), license=val("LicenseShortName"),
            provenance="verified" if own else "unknown",
            provenanceReason=("Commons records the uploader as the author (\"Own work\"), license " + val("LicenseShortName") + "."
                              if own else "Commons file; credit: " + (credit or "not stated") + ". Not confirmed as the original upload.")))
    return out, "continue" in d, None


def src_openverse(q, page, kind, minres, keys, safe):
    if kind == "video":
        return [], False, "Openverse has no video search"
    params = {"q": q, "page": page, "page_size": 20, "mature": "false" if safe else "true"}
    if minres[0] >= 1920:
        params["size"] = "large"
    if kind == "animated":
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
            title=r.get("title") or "", pageUrl=r.get("foreign_landing_url", ""), thumb=r.get("thumbnail", ""),
            preview=r.get("thumbnail", ""), url=r.get("url", ""), width=w, height=h, format=fmt,
            size=int(r.get("filesize") or 0), author=r.get("creator") or "",
            license=((r.get("license") or "").upper() + " " + (r.get("license_version") or "")).strip(),
            provenance="unknown",
            provenanceReason="Openverse indexes the file from " + (r.get("source") or "a third-party site") + "; it does not verify the original upload."))
    return out, int(d.get("page_count") or 0) > page, None


def src_pexels(q, page, kind, minres, keys, safe, lang):
    key = keys.get("pexels")
    if not key:
        return None, False, "needs a free Pexels API key"
    if kind == "animated":
        return [], False, "Pexels has no GIF animations"
    hdr = {"Authorization": key}
    locale = "ru-RU" if lang == "ru" else "en-US"
    out, more = [], False
    if kind in ("all", "image"):
        params = {"query": q, "page": page, "per_page": PER_PAGE, "locale": locale}
        if minres[0] >= 3840:
            params["size"] = "large"
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
    if kind in ("all", "video"):
        params = {"query": q, "page": page, "per_page": PER_PAGE, "locale": locale}
        if minres[0]:
            params["min_width"], params["min_height"] = minres
        d = http_get("https://api.pexels.com/videos/search?" + urllib.parse.urlencode(params), hdr)
        for v in d.get("videos") or []:
            files = [f for f in (v.get("video_files") or []) if (f.get("file_type") or "").startswith("video/") and f.get("link")]
            files.sort(key=lambda f: (int(f.get("width") or 0) * int(f.get("height") or 0), float(f.get("fps") or 0)), reverse=True)
            if not files:
                continue
            best = files[0]
            pics = v.get("video_pictures") or []
            slug = urllib.parse.urlparse(v.get("url", "")).path.strip("/").split("/")[-1]
            out.append(item(
                id="pexels:v%s" % v.get("id"), source="pexels", sourceName="Pexels Video",
                title=re.sub(r"[-\d]+$", "", slug).replace("-", " ").strip() or "Pexels video",
                pageUrl=v.get("url", ""), thumb=(pics[0].get("picture") if pics else v.get("image", "")), preview=v.get("image", ""),
                url=best.get("link", ""), width=int(best.get("width") or 0), height=int(best.get("height") or 0),
                format=ext_from(best.get("file_type"), best.get("link")) or "mp4", fps=round(float(best.get("fps") or 0), 3),
                size=int(best.get("size") or 0), duration=float(v.get("duration") or 0),
                author=(v.get("user") or {}).get("name", ""), license="Pexels License", provenance="verified",
                provenanceReason="Uploaded by the author on Pexels; this is the largest rendition Pexels serves."))
        more = more or bool(d.get("next_page"))
    return out, more, None


def src_pixabay(q, page, kind, minres, keys, safe, lang):
    key = keys.get("pixabay")
    if not key:
        return None, False, "needs a free Pixabay API key"
    out, more = [], False
    base = {"key": key, "q": q[:100], "page": page, "per_page": PER_PAGE, "safesearch": "true" if safe else "false",
            "lang": "ru" if lang == "ru" else "en"}
    if minres[0]:
        base["min_width"], base["min_height"] = minres
    if kind in ("all", "image", "animated"):
        d = http_get("https://pixabay.com/api/?" + urllib.parse.urlencode(base))
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
            fmt = ext_from("", url) or "jpg"
            if kind == "animated" and fmt != "gif":
                continue
            out.append(item(
                id="pixabay:i%s" % h.get("id"), source="pixabay", sourceName="Pixabay",
                title=h.get("tags") or "Pixabay image", pageUrl=h.get("pageURL", ""), thumb=h.get("previewURL", ""),
                preview=h.get("webformatURL", ""), url=url, width=w, height=hh, format=fmt,
                size=int(h.get("imageSize") or 0) if orig else 0, author=h.get("user", ""), license="Pixabay Content License",
                provenance="verified", provenanceReason="Uploaded by " + (h.get("user") or "?") + " on Pixabay.",
                notes=note, originalAvailable=orig))
        more = more or page * PER_PAGE < int(d.get("totalHits") or 0)
    if kind in ("all", "video"):
        d = http_get("https://pixabay.com/api/videos/?" + urllib.parse.urlencode(base))
        for v in d.get("hits") or []:
            vids = v.get("videos") or {}
            best = None
            for k in ("large", "medium", "small", "tiny"):
                f = vids.get(k) or {}
                if f.get("url") and int(f.get("width") or 0) > 0:
                    best = f
                    break
            if not best:
                continue
            out.append(item(
                id="pixabay:v%s" % v.get("id"), source="pixabay", sourceName="Pixabay Video",
                title=v.get("tags") or "Pixabay video", pageUrl=v.get("pageURL", ""), thumb=best.get("thumbnail", ""),
                preview=best.get("thumbnail", ""), url=best.get("url", ""), width=int(best.get("width") or 0),
                height=int(best.get("height") or 0), format="mp4", size=int(best.get("size") or 0),
                duration=float(v.get("duration") or 0), author=v.get("user", ""), license="Pixabay Content License",
                provenance="verified", provenanceReason="Uploaded by " + (v.get("user") or "?") + " on Pixabay."))
        more = more or page * PER_PAGE < int(d.get("totalHits") or 0)
    return out, more, None


def src_giphy(q, page, kind, minres, keys, safe):
    key = keys.get("giphy")
    if not key:
        return None, False, "needs a Giphy API key"
    if kind not in ("all", "animated"):
        return [], False, "Giphy hosts GIF animations only"
    params = {"api_key": key, "q": q, "limit": PER_PAGE, "offset": (page - 1) * PER_PAGE, "rating": "pg-13" if safe else "r"}
    d = http_get("https://api.giphy.com/v1/gifs/search?" + urllib.parse.urlencode(params))
    out = []
    for g in d.get("data") or []:
        im = g.get("images") or {}
        o = im.get("original") or {}
        out.append(item(
            id="giphy:" + g.get("id", ""), source="giphy", sourceName="Giphy", title=g.get("title", ""),
            pageUrl=g.get("url", ""), thumb=(im.get("fixed_width_still") or {}).get("url", ""),
            preview=(im.get("fixed_width") or {}).get("url", ""), url=o.get("url", ""),
            width=int(o.get("width") or 0), height=int(o.get("height") or 0), format="gif",
            size=int(o.get("size") or 0), author=(g.get("user") or {}).get("display_name", "") or g.get("username", ""),
            provenance="unknown", provenanceReason="Giphy does not state the origin of the animation."))
    pg = d.get("pagination") or {}
    return out, int(pg.get("offset") or 0) + int(pg.get("count") or 0) < int(pg.get("total_count") or 0), None


SOURCE_FUNCS = {
    "wallhaven": (src_wallhaven, False), "commons": (src_commons, False), "openverse": (src_openverse, False),
    "pexels": (src_pexels, True), "pixabay": (src_pixabay, True), "giphy": (src_giphy, False),
}
# Sources that understand Russian natively always get the original text.
NATIVE_RU = {"pexels", "pixabay"}


def cmd_search(a):
    query = (a.query or "").strip()
    if not query:
        emit({"ok": False, "error": "empty query"})
        return
    keys = load_keys()
    minres = RES.get(a.min, (0, 0))
    sources = [s for s in (a.sources or ",".join(ALL_SOURCES)).split(",") if s in SOURCE_FUNCS]
    lang = "ru" if has_cyrillic(query) else "en"
    translated, terr = None, None
    if lang == "ru" and a.translate == "auto" and any(s not in NATIVE_RU for s in sources):
        translated, terr = translate(query)

    def run(name):
        fn, takes_lang = SOURCE_FUNCS[name]
        use_native = name in NATIVE_RU or not translated
        q = query if use_native else translated
        t0 = time.monotonic()
        try:
            if takes_lang:
                res, more, note = fn(q, a.page, a.kind, minres, keys, a.safe, lang if use_native else "en")
            else:
                res, more, note = fn(q, a.page, a.kind, minres, keys, a.safe)
            return name, q, res, more, note, None, False, time.monotonic() - t0
        except Offline as e:
            return name, q, None, False, None, str(e), True, time.monotonic() - t0
        except SourceError as e:
            return name, q, None, False, None, str(e), False, time.monotonic() - t0
        except Exception as e:  # a malformed answer must not kill the whole search
            return name, q, None, False, None, "unexpected answer: %s" % e, False, time.monotonic() - t0

    results, status, any_more, offline_count = [], [], False, 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(sources) or 1) as ex:
        for name, q, res, more, note, err, off, dt in ex.map(run, sources):
            offline_count += 1 if off else 0
            st = {"source": name, "query": q, "count": len(res) if res else 0, "ms": int(dt * 1000)}
            if err:
                st["error"] = err
            elif res is None:
                st["skipped"] = note
            else:
                if note:
                    st["note"] = note
                elif not res:
                    st["note"] = "no results for this query"
                results.append(res)
                any_more = any_more or more
            status.append(st)

    # Interleave sources so one provider does not bury the others.
    merged, i = [], 0
    while any(i < len(r) for r in results):
        for r in results:
            if i < len(r):
                merged.append(r[i])
        i += 1
    # Client-side resolution guard for sources without a server-side filter.
    if minres[0]:
        merged = [m for m in merged if not (m["width"] and m["height"]) or (m["width"] >= minres[0] and m["height"] >= minres[1])]
    if a.kind != "all":
        merged = [m for m in merged if m["kind"] == a.kind]
    qc = read_json(QUALITY_CACHE, {})
    for m in merged:
        m["thumbCache"] = thumb_path(m["thumb"]) if m["thumb"] else ""
        m["thumbCached"] = bool(m["thumbCache"]) and os.path.exists(m["thumbCache"])
        if m["id"] in qc:
            m["quality"] = qc[m["id"]]
    tried = [s for s in status if "skipped" not in s]
    emit({
        "ok": True, "query": query, "lang": lang, "translated": translated, "translateError": terr,
        "page": a.page, "kind": a.kind, "min": a.min, "results": merged, "sources": status, "hasMore": any_more,
        "offline": bool(tried) and offline_count == len(tried),
    })


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
            return 0
        try:
            body = http_get(u, want_json=False, timeout=10)
        except Exception:
            return 0
        if len(body) > 4 * 1024 * 1024 or not sniff(body[:64]):
            return 0
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p + ".part", "wb") as f:
            f.write(body)
        os.replace(p + ".part", p)
        return 1

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
        done = sum(ex.map(fetch, urls))
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
        r = subprocess.run(["ffprobe", "-v", "error", "-show_format", "-show_streams", "-of", "json", path],
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
    vs = next((s for s in d.get("streams") or [] if s.get("codec_type") == "video"), None)
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
    elif info["format"] in ("gif", "webp"):
        frames = count_frames(path)
        info["frames"] = frames
        info["kind"] = "animated" if frames > 1 else "image"
        if frames > 1:
            info["duration"] = float(fmt.get("duration") or vs.get("duration") or 0)
            info["fps"] = round(ratio(vs.get("avg_frame_rate")), 3)
    return info


def count_frames(path):
    try:
        r = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-count_frames",
                            "-show_entries", "stream=nb_read_frames", "-of", "csv=p=0", path],
                           capture_output=True, text=True, timeout=40)
        return int((r.stdout.strip().split(",")[0] or "0"))
    except (subprocess.TimeoutExpired, ValueError):
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


def cmd_download(a):
    global _partial
    signal.signal(signal.SIGTERM, _on_term)
    signal.signal(signal.SIGINT, _on_term)
    url = a.url
    if urllib.parse.urlparse(url).scheme not in ("https", "http"):
        emit({"ok": False, "error": "only http(s) downloads are allowed"})
        return
    limit = int(a.max_mb) * 1024 * 1024
    os.makedirs(a.dest, exist_ok=True)
    base = safe_name(a.title) + "_" + safe_name(a.id.replace(":", "-"))
    _partial = os.path.join(a.dest, "." + base + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            total = int(r.headers.get("Content-Length") or 0)
            if total and total > limit:
                emit({"ok": False, "error": "file is %.1f MB, above the %d MB download limit" % (total / 1048576.0, a.max_mb)})
                return
            ctype = (r.headers.get("Content-Type") or "").split(";")[0].strip().lower()
            if ctype and not (ctype.startswith("image/") or ctype.startswith("video/") or ctype in ("application/octet-stream", "binary/octet-stream", "audio/webm")):
                # Wikimedia labels WebM videos audio/webm; the signature and the
                # ffprobe check below still reject anything without a picture stream.
                emit({"ok": False, "error": "server sent %s, not an image or video" % ctype})
                return
            done, last = 0, 0.0
            with open(_partial, "wb") as f:
                while True:
                    chunk = r.read(256 * 1024)
                    if not chunk:
                        break
                    done += len(chunk)
                    if done > limit:
                        raise SourceError("download exceeded the %d MB limit" % a.max_mb)
                    f.write(chunk)
                    now = time.monotonic()
                    if now - last > 0.25:
                        sys.stdout.write("P %d %d\n" % (done, total))
                        sys.stdout.flush()
                        last = now
            if total and done != total:
                raise SourceError("connection closed early (%d of %d bytes)" % (done, total))
    except (urllib.error.URLError, SourceError, socket.timeout, TimeoutError, OSError) as e:
        if _partial and os.path.exists(_partial):
            os.remove(_partial)
        reason = getattr(e, "reason", None) or str(e)
        emit({"ok": False, "error": "download failed: %s" % reason, "offline": isinstance(getattr(e, "reason", None), socket.gaierror)})
        return
    with open(_partial, "rb") as f:
        fmt = sniff(f.read(64))
    if not fmt:
        os.remove(_partial)
        emit({"ok": False, "error": "downloaded data is not a JPG/PNG/WebP/GIF/MP4/WebM file; it was deleted"})
        return
    final = os.path.join(a.dest, base + "." + fmt)
    os.replace(_partial, final)
    _partial = None
    os.chmod(final, 0o644)  # never executable
    info = media_info(final)
    if info.get("error"):
        os.remove(final)
        emit({"ok": False, "error": "file failed the integrity check (%s); it was deleted" % info["error"]})
        return
    try:
        meta = json.loads(a.meta) if a.meta else {}
    except ValueError:
        meta = {}
    lib = read_json(LIBRARY_FILE, {})
    lib[final] = {"id": a.id, "url": url, "title": a.title, "downloaded": datetime.datetime.now().isoformat(timespec="seconds"),
                  "source": meta.get("source", ""), "sourceName": meta.get("sourceName", ""), "pageUrl": meta.get("pageUrl", ""),
                  "author": meta.get("author", ""), "license": meta.get("license", ""),
                  "provenance": meta.get("provenance", "unknown"), "provenanceReason": meta.get("provenanceReason", "")}
    write_json_atomic(LIBRARY_FILE, lib)
    emit({"ok": True, "path": final, "info": info})


# --------------------------------------------------------------------------- quality

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
        lib = read_json(LIBRARY_FILE, {})
        src = dict(lib.get(a.input, {}))
        src.update({"editedFrom": a.input, "edit": p, "downloaded": datetime.datetime.now().isoformat(timespec="seconds"),
                    "title": (src.get("title") or os.path.basename(a.input)) + " (edited)"})
        lib[out] = src
        write_json_atomic(LIBRARY_FILE, lib)
    emit({"ok": True, "path": out, "info": res, "preview": preview})


# --------------------------------------------------------------------------- library / keys / status

def cmd_local(a):
    lib = read_json(LIBRARY_FILE, {})
    items, seen = [], set()
    for d in [d for d in a.dirs.split("|") if d]:
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
                path = os.path.join(root, fn)
                if path in seen:
                    continue
                seen.add(path)
                try:
                    st = os.stat(path)
                except OSError:
                    continue
                m = lib.get(path, {})
                items.append({"path": path, "name": fn, "format": ext, "kind": kind_of(ext), "size": st.st_size,
                              "mtime": int(st.st_mtime), "source": m.get("sourceName", ""), "title": m.get("title", "") or fn,
                              "edited": bool(m.get("editedFrom")), "hub": bool(m),
                              "provenance": m.get("provenance", ""), "provenanceReason": m.get("provenanceReason", ""), "id": m.get("id", "")})
    items.sort(key=lambda x: (not x["hub"], -x["mtime"]))
    emit({"ok": True, "items": items[:400]})


def cmd_keys(a):
    keys = load_keys()
    emit({"ok": True, "keys": {k: bool(keys.get(k)) for k in KEY_SOURCES}})


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
          "keys": {k: bool(keys.get(k)) for k in KEY_SOURCES}})


def main():
    ap = argparse.ArgumentParser(description="Serpantinum Wallpaper Hub backend")
    sp = ap.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("search")
    s.add_argument("--query", required=True)
    s.add_argument("--page", type=int, default=1)
    s.add_argument("--kind", choices=["all", "image", "animated", "video"], default="all")
    s.add_argument("--min", default="any", choices=list(RES))
    s.add_argument("--translate", choices=["auto", "off"], default="auto")
    s.add_argument("--sources", default="")
    s.add_argument("--unsafe", dest="safe", action="store_false")
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
    s.set_defaults(func=cmd_download)
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
    s.set_defaults(func=cmd_local)
    s = sp.add_parser("keys")
    s.set_defaults(func=cmd_keys)
    s = sp.add_parser("set-key")
    s.add_argument("source")
    s.set_defaults(func=cmd_set_key)
    s = sp.add_parser("status")
    s.set_defaults(func=cmd_status)
    a = ap.parse_args()
    try:
        a.func(a)
    except Exception as e:  # always answer with JSON so the UI never hangs
        emit({"ok": False, "error": "%s: %s" % (type(e).__name__, e)})


if __name__ == "__main__":
    main()
