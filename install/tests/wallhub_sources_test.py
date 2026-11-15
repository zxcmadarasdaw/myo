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
from pathlib import Path
import sys
import tempfile
import unittest
import urllib.parse

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
        for name in ("pexels", "pixabay", "giphy"):
            res, more, note = wh.SOURCE_FUNCS[name](ctx())
            self.assertIsNone(res, name)
            self.assertIn("key", note)
            self.assertEqual(wh.plan_skip(name, "all", "relevance", True, {})[0], "key")
        self.assertIsNone(wh.plan_skip("pexels", "all", "relevance", True, {"pexels": True}))

    def test_no_key_is_embedded_in_the_source(self):
        text = (ROOT / "src/scripts/wallpaper/wallhub.py").read_text(encoding="utf-8")
        for pattern in ("563492ad6f917", "api_key=dc6zaTOxFJmzC"):  # well-known public demo keys
            self.assertNotIn(pattern, text)
        self.assertEqual(wh.load_keys(), {})

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
        wh.src_giphy(ctx(keys={"giphy": "g" * 20}, safe=False))
        self.assertEqual(net.params()["rating"], "r", "even with Safe Search off, adult (NC-17) content is never requested")
        self.assertEqual(wh.src_giphy(ctx(keys={"giphy": "g" * 20}, kind="video"))[0], [])

    def test_safe_search_planning(self):
        self.assertEqual(wh.plan_skip("commons", "all", "relevance", True, {})[0], "safe")
        self.assertIsNone(wh.plan_skip("commons", "all", "relevance", False, {}))
        self.assertEqual(wh.plan_skip("wallhaven", "video", "relevance", True, {})[0], "kind")
        self.assertEqual(wh.plan_skip("openverse", "all", "popular", True, {})[0], "sort-popular")


class Library(unittest.TestCase):
    def test_cache_thumbs_reports_each_file(self):
        orig = wh.http_get
        good, bad = "https://example.org/a.png", "https://example.org/b.png"

        def fake(url, headers=None, timeout=None, want_json=True, retries=1):
            if url == bad:
                raise wh.SourceError("HTTP 424")
            return PNG
        wh.http_get = fake
        out = io.StringIO()
        try:
            sys.stdin = io.StringIO(json.dumps([good, bad]) + "\n")
            with contextlib.redirect_stdout(out):
                wh.cmd_cache_thumbs(None)
        finally:
            wh.http_get = orig
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
