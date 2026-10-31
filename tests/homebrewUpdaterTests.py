#!/usr/bin/env python3
"""Exercise package routing with an isolated Homebrew installation."""

import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest


class HomebrewUpdaterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="kinetic-updater-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bundle = self.root / "brew/Cellar/kinetic/0.1.0/Kinetic.app"
        contents = self.bundle / "Contents"
        contents.mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "top.frameworksdev.kinetic",
            "CFBundleShortVersionString": "0.1.0",
        }))
        self.receipt = self.bundle.parent / "INSTALL_RECEIPT.json"
        self.receipt.write_text(json.dumps({"source": {"tap": "hexadecimall/kinetic"}}))
        applications = self.root / "home/Applications"
        applications.mkdir(parents=True)
        self.link = applications / "Kinetic.app"
        self.link.symlink_to(self.bundle)
        brew = self.root / "brew/bin/brew"
        brew.parent.mkdir(parents=True)
        brew.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$HOME/commands"
test "$HOMEBREW_NO_INSTALL_CLEANUP" = 1 || exit 8
case "$1" in
  update) test ! -f "$HOME/fail" || { echo "refresh failed" >&2; exit 9; } ;;
  upgrade) ;;
  info) printf '%s\\n' '{"formulae":[{"full_name":"hexadecimall/kinetic/kinetic","versions":{"stable":"0.1.0"},"outdated":false}]}' ;;
  *) exit 7 ;;
esac
''')
        brew.chmod(0o755)
        self.environment = dict(os.environ, HOME=str(self.root / "home"))

    def runClient(self, action):
        return subprocess.run([client, "app", action, "--yes"], env=self.environment,
                              text=True, capture_output=True, timeout=20)

    def testUpdateDelegatesAndPreservesSymlink(self):
        result = self.runClient("update")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "home/commands").read_text().splitlines(), [
            "update", "upgrade --formula hexadecimall/kinetic/kinetic",
            "info --json=v2 --formula hexadecimall/kinetic/kinetic",
        ])
        self.assertTrue(self.link.is_symlink())
        self.assertTrue(self.bundle.is_dir())

    def testRefreshFailureStopsUpgrade(self):
        (self.root / "home/fail").touch()
        result = self.runClient("update")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refresh failed", result.stderr)
        self.assertEqual((self.root / "home/commands").read_text(), "update\n")

    def testCheckUsesFormulaInsteadOfRelease(self):
        result = self.runClient("check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("current in Homebrew", result.stdout)

    def testOtherTapIsNotModified(self):
        self.receipt.write_text(json.dumps({"source": {"tap": "another/tap"}}))
        self.assertNotEqual(self.runClient("update").returncode, 0)
        self.assertFalse((self.root / "home/commands").exists())

    def testUninstallPreservesManagedApp(self):
        result = self.runClient("uninstall")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("brew uninstall", result.stderr)
        self.assertTrue(self.link.is_symlink())


if __name__ == "__main__":
    client = str(Path(sys.argv.pop(1)).resolve())
    unittest.main()
