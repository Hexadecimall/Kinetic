import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


root = Path(__file__).resolve().parent.parent
sourceApp = root / "build/debug/Kinetic.app"


@unittest.skipUnless(sys.platform == "darwin" and sourceApp.is_dir(), "requires a macOS debug build")
class InstallTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="kinetic-install-test-")
        self.addCleanup(self.directory.cleanup)
        self.base = Path(self.directory.name)
        self.appDir = self.base / "Applications"
        self.binDir = self.base / "bin"
        self.env = dict(os.environ, KINETIC_APP_DIR=str(self.appDir), KINETIC_BIN_DIR=str(self.binDir))

    def install(self, app=sourceApp):
        return subprocess.run([str(root / "scripts/install"), "--app", str(app)],
                              env=self.env, capture_output=True, text=True)

    def testSignedInstallAndExistingAppPreserved(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        installed = self.appDir / "Kinetic.app"
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(installed)], check=True)
        self.assertEqual((self.binDir / "kinetic").resolve(),
                         (installed / "Contents/Resources/bin/kinetic").resolve())
        version = subprocess.check_output([str(self.binDir / "kinetic"), "--version"], text=True)
        self.assertTrue(version.startswith("kinetic "))
        before = (installed / "Contents/_CodeSignature/CodeResources").read_bytes()
        self.assertNotEqual(self.install().returncode, 0)
        self.assertEqual((installed / "Contents/_CodeSignature/CodeResources").read_bytes(), before)
        self.assertEqual(list(self.appDir.glob(".kinetic-install.*")), [])

    def testRejectsTamperedBundleBeforeResigning(self):
        tampered = self.base / "Tampered.app"
        shutil.copytree(sourceApp, tampered)
        (tampered / "Contents/Resources/Kinetic.icns").write_bytes(b"invalid resource")
        self.assertNotEqual(self.install(tampered).returncode, 0)
        self.assertFalse((self.appDir / "Kinetic.app").exists())
        self.assertFalse((self.binDir / "kinetic").is_symlink())

    def testSigningFailureDoesNotPublish(self):
        commands = self.base / "commands"
        commands.mkdir()
        signer = commands / "codesign"
        signer.write_text('#!/bin/sh\nif [ "$1" = "--verify" ]; then exit 0; fi\nexit 1\n')
        signer.chmod(0o755)
        self.env["PATH"] = str(commands) + os.pathsep + os.environ["PATH"]
        self.assertNotEqual(self.install().returncode, 0)
        self.assertFalse((self.appDir / "Kinetic.app").exists())
        self.assertFalse((self.binDir / "kinetic").is_symlink())
        self.assertEqual(list(self.appDir.glob(".kinetic-install.*")), [])
