"""Music theme imports allow only appearance, never audio commands/settings."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]/"src/scripts/themess"))
from schema import widget_layout


class MusicThemeTests(unittest.TestCase):
    caps = {"widgetTypes": {"music": ["full", "compactGlass", "minimal", "albumCover", "vinyl", "neonMusic", "floatingPlayer"]}}
    widget = dict(id="music", type="music", variant="compactGlass", x=100, y=120, w=340, h=140)

    def test_appearance_roundtrip_for_all_new_variants(self):
        for variant in self.caps["widgetTypes"]["music"]:
            source = dict(self.widget, variant=variant, musicDrawer=True, musicAnimations=False,
                          musicVisualizer=True, musicMaterial="mica")
            result = widget_layout([source],self.caps)[0]
            self.assertEqual(result["wVariant"],variant)
            self.assertEqual(result["wX"],100)
            self.assertEqual(result["musicMaterial"],"mica")

    def test_rejects_audio_and_executable_properties(self):
        for key, value in (("preset","Rock"), ("effects",True), ("b1",12), ("onCompleted","evil()"),
                           ("command","touch /tmp/evil"), ("wProps",{"preset":"Rock"}),
                           ("musicMaterial","custom.qml"), ("musicAnimations","false")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                widget_layout([dict(self.widget, **{key:value})],self.caps)


if __name__ == "__main__":
    unittest.main()
