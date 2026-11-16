"""Offline checks of scripts/wallpaper/wallhub.py (Search Wallpapers backend).

    python3 install/tests/wallhub_sources_test.py

Pexels, Pixabay and Giphy only answer with the user's own API key, so their parsers
are checked here against responses shaped like the providers' documented API
answers (no network). The keyless sources (Wallhaven, Wikimedia Commons, Openverse)
and the whole UI are checked against the live APIs by wallpaper_search_live_test.py.
"""
import contextlib
import importlib.util
import io
import json
import os
import base64
import argparse
from pathlib import Path
import sys
import tempfile
import unittest
import urllib.parse
import shutil
import subprocess
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
TMP = tempfile.mkdtemp(prefix="serp-wallhub-")
os.environ["HOME"] = TMP
os.environ["XDG_CONFIG_HOME"] = os.path.join(TMP, ".config")
os.environ["QS_STATE_DIR"] = os.path.join(TMP, "state")
os.environ["QS_CACHE_DIR"] = os.path.join(TMP, "cache")

spec = importlib.util.spec_from_file_location("wallhub", ROOT / "src/scripts/wallpaper/wallhub.py")
wh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wh)

PNG = b"\x89PNG\r\n\x1a\n" + b"\0" * 64


class FakeNet(object):
    """Stands in for http_get: records each request and answers from a table."""

    def __init__(self, answers):
        self.answers = answers
        self.calls = []

    def __call__(self, url, headers=None, timeout=None, want_json=True, retries=1):
        self.calls.append((url, dict(headers or {})))
        for prefix, body in self.answers:
            if url.startswith(prefix):
                return body
        raise AssertionError("unexpected request " + url)

    def params(self, i=-1):
        return dict(urllib.parse.parse_qsl(urllib.parse.urlparse(self.calls[i][0]).query))


def ctx(**kw):
    base = dict(q="cyberpunk night", lang="en", page=1, kind="all", minres=(0, 0), sort="relevance", safe=True, keys={})
    base.update(kw)
    return wh.Ctx(**base)


class Sources(unittest.TestCase):
    def setUp(self):
        self._orig = wh.http_get

    def tearDown(self):
        wh.http_get = self._orig

    def test_keyed_sources_never_run_without_the_users_key(self):
        for name in ("pexels", "pixabay", "giphy", "brave"):
            res, more, note = wh.SOURCE_FUNCS[name](ctx())
            self.assertIsNone(res, name)
            self.assertIn("key", note)
            self.assertEqual(wh.plan_skip(name, "all", "relevance", True, {})[0], "key")
        self.assertIsNone(wh.plan_skip("pexels", "all", "relevance", True, {"pexels": True}))

    def test_brave_uses_documented_endpoints_and_distinguishes_media_from_pages(self):
        net = FakeNet([
            ("https://api.search.brave.com/res/v1/images/search?", {"results": [
                {"url": "https://example.test/bmw", "title": "BMW", "properties": {
                    "url": "https://cdn.example.test/bmw.jpg", "width": 3840, "height": 2160},
                 "thumbnail": {"src": "https://thumb.example.test/bmw.webp", "width": 500}}]}),
            ("https://api.search.brave.com/res/v1/videos/search?", {"results": [
                {"url": "https://example.test/watch", "video": {"duration": "1:20"}},
                {"url": "https://example.test/clip.webm"},
                {"url": "https://example.test/paid.mp4", "video": {"requires_subscription": True}},
                {"url": "file:///private"}]})
        ])
        wh.http_get = net
        keys = {"brave": "example-key"}
        images, more, _ = wh.src_brave(ctx(q="BMW M5 night rain", kind="image", keys=keys))
        self.assertFalse(more)
        self.assertEqual((images[0]["width"], images[0]["pageUrl"]), (3840, "https://example.test/bmw"))
        self.assertEqual(net.params()["q"], "BMW M5 night rain")
        self.assertNotIn("offset", net.params())
        self.assertEqual(wh.src_brave(ctx(kind="image", page=2, keys=keys))[0], [])
        vids, _, _ = wh.src_brave(ctx(q="космос 4K", kind="video", page=2, lang="ru", keys=keys))
        self.assertEqual(len(vids), 3)
        self.assertEqual((vids[0]["kind"], vids[0]["duration"], vids[0]["url"]), ("video", 80, ""))
        self.assertEqual(vids[1]["format"], "webm")
        self.assertTrue(vids[2]["external"])
        self.assertEqual(net.params()["offset"], "1")
        self.assertEqual(net.params()["safesearch"], "strict")
        self.assertEqual(net.params()["search_lang"], "ru")
        self.assertEqual(net.calls[-1][1], {"X-Subscription-Token": "example-key"})
        self.assertNotIn("example-key", net.calls[-1][0])

    def test_sepia_search_keeps_safe_public_video_pages(self):
        net = FakeNet([("https://sepiasearch.org/api/v1/search/videos?", {"total": 80, "data": [
            {"url": "https://example.test/w/id", "name": "Loop", "nsfw": False, "thumbnailPath": "/thumb.jpg"},
            {"url": "https://example.test/w/live", "nsfw": False, "isLive": True},
            {"url": "https://example.test/w/adult", "nsfw": True}]})])
        wh.http_get = net
        rows, more, _ = wh.src_sepia(ctx(kind="video", page=2))
        self.assertTrue(more)
        self.assertEqual(len(rows), 1)
        self.assertTrue(rows[0]["external"])
        self.assertEqual(rows[0]["thumb"], "https://example.test/thumb.jpg")
        self.assertEqual(net.params()["nsfw"], "false")
        self.assertEqual(net.params()["start"], "24")

    def test_peertube_only_exposes_renditions_when_public_download_is_enabled(self):
        data = {"privacy": {"id": 1}, "downloadEnabled": True, "nsfw": False, "files": [
            {"fileUrl": "https://peer.test/small.mp4", "fileDownloadUrl": "https://peer.test/dl/small.mp4",
             "width": 640, "height": 360, "hasVideo": True},
            {"fileUrl": "https://peer.test/large.mp4", "fileDownloadUrl": "https://peer.test/dl/large.mp4",
             "width": 3840, "height": 2160, "hasVideo": True}]}
        args = argparse.Namespace(page_url="https://peer.test/w/example", uuid="162f04be-f987-4e19-978a-45d6eb4c5857", safe=True)

        def resolve(payload):
            with patch.object(wh, "open_media", return_value=io.BytesIO(json.dumps(payload).encode())), \
                    patch.object(wh, "require_public_url"), contextlib.redirect_stdout(io.StringIO()) as out:
                wh.cmd_peertube(args)
            return json.loads(out.getvalue())["media"]

        row = resolve(data)
        self.assertEqual(row["previewVideo"], "https://peer.test/small.mp4")
        self.assertEqual(row["url"], "https://peer.test/dl/large.mp4")
        self.assertEqual(row["width"], 3840)
        self.assertEqual(resolve(dict(data, downloadEnabled=False)), {})
        self.assertEqual(resolve(dict(data, nsfw=True)), {})

    def test_all_sources_isolates_a_failure_and_keeps_each_provider_page(self):
        seen = {}

        def good(c):
            seen["wallhaven"] = c.page
            return [wh.item(id="still", format="jpg")], True, None

        def failing(c):
            seen["openverse"] = c.page
            raise wh.SourceError("HTTP 503")

        def unused(c):
            raise AssertionError("exhausted sources must not be retried")

        args = argparse.Namespace(query="wallpaper", kind="image", sort="relevance", min="any", safe=True, page=3,
                                  sources="wallhaven,openverse,brave", source_pages='{"openverse": 2, "wallhaven": 3}',
                                  dir=[], translate="off", remember=False, include_unknown=True)
        with patch.dict(wh.SOURCE_FUNCS, wallhaven=good, openverse=failing, brave=unused), contextlib.redirect_stdout(io.StringIO()) as out:
            wh.cmd_search(args)
        events = [json.loads(line) for line in out.getvalue().splitlines()]
        sources = {event["source"]: event for event in events if event["event"] == "source"}
        self.assertEqual(seen, {"wallhaven": 3, "openverse": 2})
        self.assertEqual(sources["openverse"]["status"]["error"], "HTTP 503")
        self.assertEqual(sources["wallhaven"]["results"][0]["id"], "still")
        self.assertTrue(events[-1]["hasMore"])

    def test_no_key_is_embedded_in_the_source(self):
        text = (ROOT / "src/scripts/wallpaper/wallhub.py").read_text(encoding="utf-8")
        for pattern in ("563492ad6f917", "api_key=dc6zaTOxFJmzC"):  # well-known public demo keys
            self.assertNotIn(pattern, text)
        self.assertEqual(wh.load_keys(), {})

    def test_filters_keep_unknown_option_and_do_not_call_it_4k(self):
        unknown = wh.item(id="unknown", kind="video")
        small = wh.item(id="small", kind="video", width=1280, height=720)
        portrait = wh.item(id="portrait", kind="video", width=2160, height=3840)
        still = wh.item(id="still", format="png", width=8000, height=4500)
        self.assertEqual(wh.guard([unknown, small, portrait, still], "video", wh.RES["4k"], True),
                         ([unknown, portrait], {"lowres": 1, "kind": 1}))
        self.assertEqual(wh.guard([unknown], "video", wh.RES["4k"]), ([], {"unknownRes": 1}))
        self.assertEqual(wh.guard([portrait], "video", wh.RES["8k"]), ([], {"lowres": 1}))

    def test_gif_frame_check_ignores_the_static_thumbnail(self):
        one = base64.b64decode("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")
        frame = one[one.index(b","):-1]
        two = one[:-1] + frame + b";"
        self.assertEqual(wh.animation_frames(io.BytesIO(one), "gif"), 1)
        self.assertEqual(wh.animation_frames(io.BytesIO(two), "gif"), 2)
        self.assertEqual(wh.animation_frames(io.BytesIO(two[:-5]), "gif"), 0)
        result = wh.item(format="gif", animationFrames=2, url="https://origin.test/animated.gif",
                         thumb="https://origin.test/still.jpg")
        wh.resolve_animation(result)
        self.assertEqual((result["kind"], result["previewAnimation"]), ("animated", result["url"]))

    def test_commons_video_uses_only_compatible_small_derivatives_for_preview(self):
        net = FakeNet([("https://commons.wikimedia.org/w/api.php?", {"query": {"pages": {
            "1": {"pageid": 1, "title": "File:Night.webm", "videoinfo": [{
                "url": "https://commons.test/full.webm", "mime": "video/webm; codecs=vp9", "width": 3840, "height": 2160,
                "thumburl": "https://commons.test/still.jpg", "derivatives": [
                    {"src": "https://commons.test/full.webm", "type": "video/webm", "width": 3840, "height": 2160},
                    {"src": "https://commons.test/480p.webm", "type": "video/webm", "width": 854, "height": 480}]}]}}}})])
        wh.http_get = net
        rows, _, _ = wh.src_commons(ctx(kind="video"))
        self.assertEqual(net.params()["prop"], "videoinfo")
        self.assertEqual((rows[0]["previewVideo"], rows[0]["url"]),
                         ("https://commons.test/480p.webm", "https://commons.test/full.webm"))

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "needs ffmpeg and ffprobe")
    def test_download_checks_bytes_before_replacing_a_wallpaper(self):
        with tempfile.TemporaryDirectory(dir=TMP) as td:
            clip = Path(td) / "demo.mp4"
            subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=64x48:rate=4",
                            "-t", "1", "-c:v", "mpeg4", str(clip)], check=True)
            data = clip.read_bytes()
            args = dict(dest=td, identity="test:existing", title="demo", meta={}, limit=1024 * 1024,
                        mime="video/mp4", kind="video")
            with contextlib.redirect_stdout(io.StringIO()) as output:
                record = wh.save_media(io.BytesIO(data), total=len(data), **args)
                with self.assertRaises(wh.InvalidMedia):
                    wh.save_media(io.BytesIO(b"<html>not a movie</html>"), **args)
                self.assertIn("P ", output.getvalue())
            self.assertEqual(record["info"]["kind"], "video")
            self.assertEqual(Path(record["path"]).read_bytes(), data)
            self.assertEqual(list(Path(td).glob("*.part")), [])

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "needs ffmpeg and ffprobe")
    def test_import_apng_for_conversion_without_replacing_the_original(self):
        with tempfile.TemporaryDirectory(dir=TMP) as td:
            anim = Path(td) / "motion #1.apng"
            dest = Path(td) / "library"
            subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc=size=64x48:rate=4",
                            "-t", "1", "-f", "apng", str(anim)], check=True)
            capture = io.StringIO()
            with contextlib.redirect_stdout(capture), patch.object(wh, "STATE_DIR", td):
                wh.cmd_import(argparse.Namespace(files=[anim.as_uri()], dest=str(dest), max_mb=1))
                imported = json.loads(capture.getvalue().splitlines()[-1])["items"][0]
                wh.cmd_prepare_animation(argparse.Namespace(path=imported["path"]))
            converted = json.loads(capture.getvalue().splitlines()[-1])
            self.assertEqual(imported["info"]["format"], "apng")
            self.assertEqual(Path(imported["path"]).read_bytes(), anim.read_bytes())
            self.assertEqual(wh.media_info(converted["path"])["kind"], "video")

    def test_pexels_photos_and_videos(self):
        net = wh.http_get = FakeNet([
            ("https://api.pexels.com/v1/search", {"photos": [{
                "id": 101, "width": 6000, "height": 4000, "url": "https://www.pexels.com/photo/neon-101/",
                "photographer": "A. Author", "alt": "Neon street at night",
                "src": {"original": "https://images.pexels.com/photos/101/pexels-photo-101.jpeg",
                        "large2x": "https://images.pexels.com/photos/101/pexels-photo-101.jpeg?w=1880",
                        "medium": "https://images.pexels.com/photos/101/pexels-photo-101.jpeg?h=350"}}],
                "next_page": "https://api.pexels.com/v1/search/?page=2"}),
            ("https://api.pexels.com/videos/search", {"videos": [{
                "id": 202, "url": "https://www.pexels.com/video/city-lights-at-night-202/", "duration": 14,
                "image": "https://images.pexels.com/videos/202/poster.jpeg", "user": {"name": "B. Author"},
                "video_pictures": [{"picture": "https://images.pexels.com/videos/202/pictures/preview-0.jpg"}],
                "video_files": [
                    {"link": "https://videos.pexels.com/video-files/202/202-sd_640_360_25fps.mp4", "file_type": "video/mp4", "width": 640, "height": 360, "fps": 25},
                    {"link": "https://videos.pexels.com/video-files/202/202-uhd_3840_2160_25fps.mp4", "file_type": "video/mp4", "width": 3840, "height": 2160, "fps": 25, "size": 50000000},
                    {"link": "https://videos.pexels.com/video-files/202/202-hd_1920_1080_25fps.mp4", "file_type": "video/mp4", "width": 1920, "height": 1080, "fps": 25}]}]}),
        ])
        res, more, note = wh.src_pexels(ctx(keys={"pexels": "user-key-123"}, minres=(3840, 2160), lang="ru"))
        self.assertTrue(more)
        self.assertEqual(net.calls[0][1].get("Authorization"), "user-key-123", "the key goes in the header, not the URL")
        self.assertNotIn("user-key-123", net.calls[0][0])
        p = net.params(0)
        self.assertEqual((p["orientation"], p["size"], p["locale"]), ("landscape", "small", "ru-RU"))
        self.assertEqual(net.params(1)["min_width"], "3840")
        photo, video = res
        self.assertEqual((photo["kind"], photo["format"], photo["width"], photo["height"]), ("image", "jpg", 6000, 4000))
        self.assertTrue(photo["url"].endswith("pexels-photo-101.jpeg"))
        self.assertEqual((video["kind"], video["format"], video["width"], video["height"]), ("video", "mp4", 3840, 2160))
        self.assertIn("uhd_3840_2160", video["url"], "the largest rendition is the original")
        self.assertIn("sd_640_360", video["previewVideo"], "preview streams the smallest rendition at least 640 px wide, never the 4K file")
        self.assertEqual(video["duration"], 14.0)

    def test_pixabay_reports_reduced_copies_honestly(self):
        net = wh.http_get = FakeNet([
            ("https://pixabay.com/api/videos/", {"totalHits": 1, "hits": [{
                "id": 7, "pageURL": "https://pixabay.com/videos/id-7/", "tags": "night, city", "duration": 20, "user": "u",
                "videos": {"large": {"url": "https://cdn.pixabay.com/video/7_large.mp4", "width": 3840, "height": 2160, "size": 40000000, "thumbnail": "https://cdn.pixabay.com/video/7_large.jpg"},
                           "medium": {"url": "https://cdn.pixabay.com/video/7_medium.mp4", "width": 1920, "height": 1080, "size": 9000000, "thumbnail": ""},
                           "small": {"url": "https://cdn.pixabay.com/video/7_small.mp4", "width": 1280, "height": 720, "size": 4000000, "thumbnail": ""},
                           "tiny": {"url": "", "width": 0, "height": 0}}}]}),
            ("https://pixabay.com/api/", {"totalHits": 40, "hits": [{
                "id": 5, "pageURL": "https://pixabay.com/photos/id-5/", "tags": "cyberpunk", "user": "u",
                "imageWidth": 6000, "imageHeight": 4000, "imageSize": 9000000,
                "previewURL": "https://cdn.pixabay.com/photo/5_150.jpg", "webformatURL": "https://pixabay.com/get/5_640.jpg",
                "largeImageURL": "https://pixabay.com/get/5_1280.jpg"}]}),
        ])
        res, more, _ = wh.src_pixabay(ctx(keys={"pixabay": "k" * 20}, sort="newest", safe=True))
        self.assertTrue(more)
        p = net.params(0)
        self.assertEqual((p["safesearch"], p["order"]), ("true", "latest"))
        img, vid = res
        self.assertFalse(img["originalAvailable"], "without full API access only the 1280 px copy exists")
        self.assertEqual((img["width"], img["height"]), (1280, 853))
        self.assertEqual(img["size"], 0, "the 6000 px file size must not be shown for the 1280 px copy")
        self.assertTrue(img["notes"])
        self.assertEqual((vid["width"], vid["height"], vid["format"]), (3840, 2160, "mp4"))
        self.assertTrue(vid["previewVideo"].endswith("7_small.mp4"))
        wh.src_pixabay(ctx(keys={"pixabay": "k" * 20}, safe=False))
        self.assertEqual(net.params(-1)["safesearch"], "false")

    def test_giphy_uses_its_rating_filter_and_only_animations(self):
        net = wh.http_get = FakeNet([("https://api.giphy.com/v1/gifs/search", {"data": [{
            "id": "abc", "title": "Neon rain", "url": "https://giphy.com/gifs/abc", "import_datetime": "2024-03-01 10:00:00",
            "images": {"original": {"url": "https://media.giphy.com/media/abc/giphy.gif", "width": "480", "height": "270", "size": "2500000"},
                       "fixed_width_still": {"url": "https://media.giphy.com/media/abc/200w_s.gif"},
                       "fixed_width": {"url": "https://media.giphy.com/media/abc/200w.gif"}}}],
            "pagination": {"total_count": 60, "count": 25, "offset": 0}})])
        res, more, _ = wh.src_giphy(ctx(keys={"giphy": "g" * 20}, kind="animated"))
        self.assertEqual(net.params()["rating"], "pg")
        self.assertTrue(more)
        self.assertEqual((res[0]["kind"], res[0]["format"], res[0]["width"], res[0]["provenance"]), ("animated", "gif", 480, "unknown"))
        self.assertEqual(res[0]["url"], "")
        self.assertTrue(res[0]["external"])
        wh.src_giphy(ctx(keys={"giphy": "g" * 20}, safe=False))
        self.assertEqual(net.params()["rating"], "r", "even with Safe Search off, adult (NC-17) content is never requested")
        self.assertEqual(wh.src_giphy(ctx(keys={"giphy": "g" * 20}, kind="video"))[0], [])

    def test_safe_search_planning(self):
        self.assertEqual(wh.plan_skip("commons", "all", "relevance", True, {})[0], "safe")
        self.assertIsNone(wh.plan_skip("commons", "all", "relevance", False, {}))
        self.assertEqual(wh.plan_skip("wallhaven", "video", "relevance", True, {})[0], "kind")
        self.assertEqual(wh.plan_skip("openverse", "all", "popular", True, {})[0], "sort-popular")
        self.assertEqual(wh.plan_skip("links", "video", "relevance", True, {})[0], "safe")

    def test_steam_video_pages_use_the_official_workshop_query(self):
        net = FakeNet([("https://api.steampowered.com/IPublishedFileService/QueryFiles/v1/", {
            "response": {"total": 1, "publishedfiledetails": [{"publishedfileid": "123", "title": "Night drive"}]}})])
        wh.http_get = net
        rows, more, _ = wh.src_steam(ctx(kind="video", keys={"steam": "fixture-key"}))
        params = json.loads(net.params()["input_json"])
        self.assertEqual(params["appid"], 431960)
        self.assertEqual(params["requiredtags"], ["Video"])
        self.assertFalse(more)
        self.assertEqual(rows[0]["pageUrl"], "https://steamcommunity.com/sharedfiles/filedetails/?id=123")
        self.assertTrue(rows[0]["external"])

    def test_custom_feed_search_and_file_url_filter(self):
        feed = b"""<?xml version="1.0"?><rss><channel><item><title>Night rain</title>
        <link>https://example.org/post</link><enclosure url="/best.webm" type="video/webm" />
        <enclosure url="file:///private.mp4" type="video/mp4" /></item></channel></rss>"""
        with patch.object(wh, "open_media", return_value=io.BytesIO(feed)):
            rows, more, _ = wh.src_links(ctx(q="night rain", kind="video", urls=["https://example.org/feed"]))
        self.assertFalse(more)
        self.assertEqual([(r["url"], r["kind"]) for r in rows], [("https://example.org/best.webm", "video")])

    def test_local_source_searches_unicode_names(self):
        with tempfile.TemporaryDirectory(dir=TMP) as td:
            path = Path(td) / "\u043a\u043e\u0441\u043c\u043e\u0441 4K.png"
            path.write_bytes(PNG)
            rows, more, _ = wh.src_local(ctx(q="\u043a\u043e\u0441\u043c\u043e\u0441 4k", dirs=[td], kind="image"))
            self.assertEqual([r["path"] for r in rows], [str(path)])
            self.assertTrue(rows[0]["local"])
            self.assertFalse(more)


class Library(unittest.TestCase):
    def test_cache_thumbs_reports_each_file(self):
        orig = wh.open_media
        good, bad = "https://example.org/a.png", "https://example.org/b.png"

        def fake(url, *, timeout, headers=None):
            if url == bad:
                raise wh.SourceError("HTTP 424")
            return io.BytesIO(PNG)
        wh.open_media = fake
        out = io.StringIO()
        try:
            sys.stdin = io.StringIO(json.dumps([good, bad]) + "\n")
            with contextlib.redirect_stdout(out):
                wh.cmd_cache_thumbs(None)
        finally:
            wh.open_media = orig
            sys.stdin = sys.__stdin__
        lines = [json.loads(l) for l in out.getvalue().splitlines()]
        ev = {l["url"]: l for l in lines if l.get("event") == "thumb"}
        self.assertTrue(os.path.isfile(ev[good]["path"]) and not ev[good]["failed"])
        self.assertTrue(ev[bad]["failed"] and ev[bad]["path"] == "")
        self.assertEqual(lines[-1], {"ok": True, "cached": 1})

    def test_local_lists_each_file_once(self):
        wp = os.path.join(TMP, "Wallpapers")
        hub = os.path.join(wp, "Wallpaper Hub")
        os.makedirs(hub, exist_ok=True)
        with open(os.path.join(hub, "x.png"), "wb") as f:
            f.write(PNG)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            wh.cmd_local(type("A", (), {"dirs": wp + "|" + hub + "|" + hub.replace(os.sep, "/")})())
        items = json.loads(out.getvalue().splitlines()[-1])["items"]
        self.assertEqual(len(items), 1)


if __name__ == "__main__":
    unittest.main(verbosity=1)
