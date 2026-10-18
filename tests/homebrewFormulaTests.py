import hashlib
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest


root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("generateHomebrewFormula", root / "scripts/generateHomebrewFormula.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class HomebrewFormulaTests(unittest.TestCase):
    def testSourceVersionChecksumAndNoToolchainDependency(self):
        commit = "a" * 40
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "source.tar.gz"
            with tarfile.open(archive, "w:gz") as source:
                version = b"0.31.2\n"
                entry = tarfile.TarInfo(f"Kinetic-{commit}/VERSION")
                entry.size = len(version)
                source.addfile(entry, io.BytesIO(version))
            text = module.renderFormula(root, archive, commit)
            self.assertIn(hashlib.sha256(archive.read_bytes()).hexdigest(), text)
            self.assertIn(f"/archive/{commit}.tar.gz", text)
            self.assertIn('version "0.31.2"', text)
            self.assertNotIn('depends_on "llvm', text)
            self.assertNotIn('depends_on "rust"', text)
            self.assertIn('CARGO_NET_OFFLINE', text)
            self.assertIn('refute_path_exists', text)
            self.assertNotIn('bottle do', text)
            self.assertIn('post_install_steps do', text)
            self.assertEqual(text.count('"--force", "--sign", "-"'), 3)

    def testRejectsUnpinnedRevision(self):
        with self.assertRaises(ValueError):
            module.renderFormula(root, Path("unused.tar.gz"), "main")
