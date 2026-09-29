import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("generateHomebrew", root / "scripts/generateHomebrew.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class HomebrewTests(unittest.TestCase):
    def fixture(self, directory, version=None, llvm=False):
        current = (root / "VERSION").read_text().strip()
        archive = Path(directory) / f"Kinetic-{current}-macos-arm64.zip"
        with zipfile.ZipFile(archive, "w") as bundle:
            bundle.writestr("Kinetic.app/Contents/Info.plist", plistlib.dumps({
                "CFBundleShortVersionString": version or current,
                "CFBundleIdentifier": "top.frameworksdev.kinetic",
            }))
            bundle.writestr("Kinetic.app/Contents/Resources/bin/kinetic", b"fixture")
            if llvm:
                bundle.writestr("Kinetic.app/Contents/Resources/tools/llvm/bin/clangd", b"fixture")
        return archive

    def testExactVersionAndChecksum(self):
        with tempfile.TemporaryDirectory() as directory:
            text = module.renderCask(root, self.fixture(directory), True)
            self.assertNotIn("@SHA256@", text)
            self.assertIn("not notarized", text)
            self.assertIn('binary "#{appdir}/Kinetic.app/Contents/Resources/bin/kinetic"', text)
            self.assertIn('preflight_steps do', text)
            self.assertIn('postflight_steps do', text)
            self.assertEqual(text.count('"--force", "--sign", "-"'), 3)
            self.assertEqual(text.count('"--verify", "--deep", "--strict"'), 3)
            self.assertLess(text.index('"--verify"'), text.index('"--force"'))
            self.assertNotIn('xattr', text)
            self.assertNotIn('spctl', text)

    def testRejectsVersionMismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                module.renderCask(root, self.fixture(directory, "0.0.0"))

    def testRejectsBundledTools(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                module.renderCask(root, self.fixture(directory, llvm=True))
