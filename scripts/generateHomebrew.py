#!/usr/bin/env python3
"""Generate a versioned cask from the exact release archive."""

import argparse
import hashlib
import plistlib
import re
from pathlib import Path
import zipfile


def renderCask(root, archive, unnotarized=False):
    version = (root / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid release version")
    if archive.name != f"Kinetic-{version}-macos-arm64.zip":
        raise ValueError("Archive name and release version differ")
    with zipfile.ZipFile(archive) as bundle:
        info = plistlib.loads(bundle.read("Kinetic.app/Contents/Info.plist"))
        if info.get("CFBundleShortVersionString") != version:
            raise ValueError("App and cask versions differ")
        if info.get("CFBundleIdentifier") != "top.frameworksdev.kinetic":
            raise ValueError("Unexpected bundle identifier")
        if "Kinetic.app/Contents/Resources/bin/kinetic" not in bundle.namelist():
            raise ValueError("Archive has no embedded CLI")
        if any(name.startswith("Kinetic.app/Contents/Resources/tools/llvm/") for name in bundle.namelist()):
            raise ValueError("Release must not bundle LLVM language tools")
    with archive.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    template = (root / "packaging/homebrew/kinetic.rb.in").read_text()
    caveats = '\n  caveats "This preview is not notarized. macOS may block its first launch."' if unnotarized else ""
    return template.replace("@VERSION@", version).replace("@SHA256@", digest).replace("@CAVEATS@", caveats)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--unnotarized", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    version = (root / "VERSION").read_text().strip()
    archive = root / "dist" / f"Kinetic-{version}-macos-arm64.zip"
    output = root / "dist/homebrew/Casks/kinetic.rb"
    text = renderCask(root, archive, args.unnotarized)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text)
    print(f"Generated {output.relative_to(root)}")


if __name__ == "__main__":
    main()
