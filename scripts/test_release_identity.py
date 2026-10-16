"""Release-identity contract; run with python3 scripts/test_release_identity.py."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "NeonRacer.xcodeproj/project.pbxproj"


class ReleaseIdentityTests(unittest.TestCase):
    def test_all_six_target_configs_match_iphone_bundle_contract(self):
        project = PROJECT.read_text()
        self.assertEqual(re.findall(r'PRODUCT_BUNDLE_IDENTIFIER = "?([^";]+)"?;', project),
                         ["com.infinityball.neonracer"] * 2
                         + ["com.infinityball.neonracer.tests"] * 2
                         + ["com.infinityball.neonracer.uitests"] * 2)
        self.assertEqual(re.findall(r'TARGETED_DEVICE_FAMILY = "?([^";]+)"?;', project), ["1"] * 6)
        self.assertEqual(re.findall(r'INFOPLIST_KEY_CFBundleDisplayName = "?([^";]+)"?;', project),
                         ["Neon Racer"] * 2)
        self.assertNotIn("INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad", project)

        # Canary: reintroducing the inherited iPad family must flip the check.
        ipad = project.replace('TARGETED_DEVICE_FAMILY = 1;', 'TARGETED_DEVICE_FAMILY = "1,2";', 1)
        self.assertNotEqual(re.findall(r'TARGETED_DEVICE_FAMILY = "?([^";]+)"?;', ipad), ["1"] * 6)
        # Canary: one stale hyphenated bundle id must flip the check.
        stale = project.replace('com.infinityball.neonracer"', 'com.infinityball.neon-racer"', 1)
        self.assertNotEqual(
            re.findall(r'PRODUCT_BUNDLE_IDENTIFIER = "?(com\.infinityball\.[^";]+)"?;', stale),
            ["com.infinityball.neonracer"] * 2
            + ["com.infinityball.neonracer.tests"] * 2
            + ["com.infinityball.neonracer.uitests"] * 2)

    def test_ci_asserts_built_iphone_bundle(self):
        ci = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn('CFBundleIdentifier raw "$APP/Info.plist")" = "com.infinityball.neonracer"', ci)
        self.assertIn('CFBundleDisplayName raw "$APP/Info.plist")" = "Neon Racer"', ci)
        self.assertIn('test "$FAMILY" = \'[1]\'', ci)
        self.assertNotIn("com.infinityball.neon-racer", ci)
        self.assertNotIn("'[1,2]'", ci)

    def test_release_docs_match_project_marketing_version(self):
        project = PROJECT.read_text()
        versions = re.findall(r'MARKETING_VERSION = ([^;]+);', project)
        self.assertEqual(versions, ["1.1", "1.1"])
        for name in ("docs/release.md", "Documentation/Release.md"):
            release = (ROOT / name).read_text()
            self.assertIn("marketing version: `1.1`", release)
            self.assertEqual(re.findall(r'^VERSION=(.+)$', release, re.M), ["1.1", "1.1"])
        for name in ("AppStoreAssets/README.md", "Documentation/AppStoreMetadata.md",
                     "docs/app-store/metadata.md"):
            self.assertNotIn("version 1.0", (ROOT / name).read_text())

    def test_one_authoritative_performance_contract(self):
        performance = (ROOT / "docs/performance.md").read_text()
        pointer = (ROOT / "Documentation/Performance.md").read_text()
        self.assertIn("A17 Pro", performance)
        self.assertIn("650 MB", performance)
        self.assertIn("docs/performance.md", pointer)
        self.assertNotIn("iPhone 11", pointer)
        self.assertNotIn("350 MB", pointer)
        self.assertIn("docs/performance.md", (ROOT / "README.md").read_text())


if __name__ == "__main__":
    unittest.main()
