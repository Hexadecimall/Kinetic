#!/usr/bin/env python3
"""Generate a source-build formula from a checksum-pinned GitHub source archive."""

import argparse
import hashlib
from pathlib import Path
import re
import tarfile


def renderFormula(root, archive, commit):
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Expected a full source commit")
    with tarfile.open(archive) as source:
        stream = source.extractfile(f"Kinetic-{commit}/VERSION")
        if stream is None:
            raise ValueError("Source archive has no version")
        version = stream.read(128).decode().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid source version")
    with archive.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    template = (root / "packaging/homebrew/kineticFormula.rb.in").read_text()
    return template.replace("@COMMIT@", commit).replace("@VERSION@", version).replace("@SHA256@", digest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--commit", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    output = root / "dist/homebrew/Formula/kinetic.rb"
    text = renderFormula(root, args.archive, args.commit)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text)
    print(f"Generated {output.relative_to(root)}")


if __name__ == "__main__":
    main()
