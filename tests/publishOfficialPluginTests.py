import struct
import tempfile
import unittest
from pathlib import Path

from scripts import publishOfficialPlugin as publisher


class PublishOfficialPluginTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.asset = Path(self.temporary.name) / publisher.assetName
        self.asset.write_bytes(struct.pack("<IIII", 0xFEEDFACF, 0x0100000C, 0, 6))

    def tearDown(self):
        self.temporary.cleanup()

    def testAcceptsArm64Asset(self):
        self.assertEqual(publisher.validateAsset(self.asset), self.asset.read_bytes())

    def testRejectsPrivatePathsAndOtherArchitectures(self):
        self.asset.write_bytes(self.asset.read_bytes() + b"/" + b"Users/runner/work/project")
        with self.assertRaisesRegex(ValueError, "private build path"):
            publisher.validateAsset(self.asset)
        self.asset.write_bytes(struct.pack("<IIII", 0xFEEDFACF, 0x01000007, 0, 6))
        with self.assertRaisesRegex(ValueError, "arm64"):
            publisher.validateAsset(self.asset)

    def testRejectsWrongNameAndSymlink(self):
        with self.assertRaisesRegex(ValueError, "first-party"):
            publisher.validateAsset(self.asset.with_name("other.dylib"))
        linkDir = self.asset.parent / "links"
        linkDir.mkdir()
        linkedAsset = linkDir / publisher.assetName
        linkedAsset.symlink_to(self.asset)
        with self.assertRaisesRegex(ValueError, "first-party"):
            publisher.validateAsset(linkedAsset)


if __name__ == "__main__":
    unittest.main()
