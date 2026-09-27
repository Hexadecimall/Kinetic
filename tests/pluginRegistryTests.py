import argparse
import hashlib
from pathlib import Path
import struct
import tempfile
import unittest

from scripts import pluginRegistry as registry


class PluginRegistryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.entryRoot = self.root / "registry" / "entries"
        self.entryRoot.mkdir(parents=True)
        (self.root / "registry" / "official.json").write_bytes(
            registry.canonicalJson({"schemaVersion": 1, "plugins": {}}))
        (self.root / "registry" / "index.json").write_bytes(
            registry.canonicalJson({"schemaVersion": 1, "plugins": []}))
        self.asset = self.root / "sample.dylib"
        self.assetBytes = struct.pack("<IIII", 0xFEEDFACF, 0x0100000C, 0, 6) + b"test"
        self.asset.write_bytes(self.assetBytes)

    def tearDown(self):
        self.temporary.cleanup()

    def draftOptions(self, pluginId="example.sample", githubId=42, version="0.1.0"):
        return argparse.Namespace(
            asset=str(self.asset),
            pluginId=pluginId,
            name="Sample Plugin",
            summary="A native test plugin",
            githubId=githubId,
            githubLogin="example",
            version=version,
            releaseUrl="https://github.com/example/plugin/releases/download/v0.1.0/sample.dylib",
        )

    def testDraftBuildsDeterministicIndex(self):
        entryPath = registry.draftEntry(self.root, self.draftOptions())
        registry.checkIndex(self.root)
        entry = registry.readJson(entryPath)
        self.assertEqual(entry["asset"]["sha256"], hashlib.sha256(self.assetBytes).hexdigest())
        index = registry.buildIndex(self.root)
        self.assertFalse(index["plugins"][0]["official"])
        self.assertEqual(index["plugins"][0]["publisher"]["githubId"], 42)
        self.assertEqual(index["plugins"][0]["releases"][0]["version"], "0.1.0")

    def testOfficialComesOnlyFromMaintainerPolicy(self):
        entryPath = registry.draftEntry(self.root, self.draftOptions())
        entry = registry.readJson(entryPath)
        entry["official"] = True
        with self.assertRaises(registry.RegistryError):
            registry.validateEntry(entry)
        (self.root / "registry" / "official.json").write_bytes(
            registry.canonicalJson({"schemaVersion": 1, "plugins": {"example.sample": 42}}))
        self.assertTrue(registry.buildIndex(self.root)["plugins"][0]["official"])
        (self.root / "registry" / "official.json").write_bytes(
            registry.canonicalJson({"schemaVersion": 1, "plugins": {"example.sample": 99}}))
        with self.assertRaises(registry.RegistryError):
            registry.buildIndex(self.root)

    def testPublishedReleaseCannotChangeOwner(self):
        registry.draftEntry(self.root, self.draftOptions())
        with self.assertRaises(registry.RegistryError):
            registry.draftEntry(self.root, self.draftOptions(githubId=99, version="0.2.0"))
        self.assertFalse((self.entryRoot / "example.sample" / "0.2.0.json").exists())

    def testRejectsReservedNamespaceAndWrongAsset(self):
        with self.assertRaises(registry.RegistryError):
            registry.draftEntry(self.root, self.draftOptions(pluginId="kinetic.sample"))
        options = self.draftOptions()
        options.releaseUrl = "https://example.invalid/plugin/sample.dylib"
        with self.assertRaises(registry.RegistryError):
            registry.draftEntry(self.root, options)
        self.asset.write_bytes(b"not Mach-O content")
        with self.assertRaises(registry.RegistryError):
            registry.draftEntry(self.root, self.draftOptions())

    def testRemoteAssetMustMatchChecksum(self):
        entryPath = registry.draftEntry(self.root, self.draftOptions())
        entry = registry.readJson(entryPath)
        registry.verifyAssets([entry], lambda url: self.assetBytes)
        with self.assertRaises(registry.RegistryError):
            registry.verifyAssets([entry], lambda url: self.assetBytes + b"x")

    def testArm64MachOBundlesAreAccepted(self):
        bundle = struct.pack("<IIII", 0xFEEDFACF, 0x0100000C, 0, 8) + b"test"
        self.assertTrue(registry.validMachO(bundle))

    def testIndexCannotBeHandEdited(self):
        registry.draftEntry(self.root, self.draftOptions())
        (self.root / "registry" / "index.json").write_text("{}\n", encoding="utf-8")
        with self.assertRaises(registry.RegistryError):
            registry.checkIndex(self.root)

    def testPullRequestCannotClaimAnotherPublisherOrOfficialStatus(self):
        registry.draftEntry(self.root, self.draftOptions())
        changes = [{"filename": "registry/entries/example.sample/0.1.0.json", "status": "added"}]
        registry.validateChangedFiles(self.root, changes, {"id": 42, "login": "example"},
                                      {"id": 1})
        with self.assertRaises(registry.RegistryError):
            registry.validateChangedFiles(self.root, changes, {"id": 77, "login": "other"},
                                          {"id": 1})
        with self.assertRaises(registry.RegistryError):
            registry.validateChangedFiles(self.root,
                                          [{"filename": "registry/official.json", "status": "modified"}],
                                          {"id": 42, "login": "example"}, {"id": 1})
        with self.assertRaises(registry.RegistryError):
            registry.validateChangedFiles(self.root,
                                          [{"filename": changes[0]["filename"], "status": "modified"}],
                                          {"id": 42, "login": "example"}, {"id": 1})


if __name__ == "__main__":
    unittest.main()
