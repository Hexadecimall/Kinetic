#!/usr/bin/env python3
"""Publish the verified first-party C/C++ plugin as an immutable GitHub Release asset."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import sys
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen


releaseTag = "cpp-support-v0.1.0"
assetName = "libkineticCppSupport.dylib"
maximumAssetBytes = 32 * 1024 * 1024


def requestJson(url, token, method="GET", payload=None):
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = Request(url, data=data, method=method, headers={
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "User-Agent": "Kinetic-Official-Plugin-Publisher",
    })
    with urlopen(request, timeout=60) as response:
        return json.load(response)


def validateAsset(assetPath):
    if assetPath.name != assetName or not assetPath.is_file() or assetPath.is_symlink():
        raise ValueError("Expected the built first-party C/C++ plugin asset")
    data = assetPath.read_bytes()
    if not 16 <= len(data) <= maximumAssetBytes:
        raise ValueError("Plugin asset exceeds the registry size limit")
    if data[:4] != b"\xcf\xfa\xed\xfe" or struct.unpack_from("<I", data, 4)[0] != 0x0100000C:
        raise ValueError("Plugin asset is not an arm64 Mach-O")
    if re.search(rb"/(?:Users|Volumes)/|/opt/Projects/", data, re.IGNORECASE):
        raise ValueError("Plugin asset contains a private build path")
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset", required=True, type=Path)
    options = parser.parse_args()
    token = os.environ.get("GITHUB_TOKEN")
    repository = os.environ.get("GITHUB_REPOSITORY")
    commit = os.environ.get("GITHUB_SHA")
    if not token or repository != "Hexadecimall/Kinetic" or not commit:
        raise ValueError("Run only in the Kinetic release workflow with GitHub credentials")

    assetPath = options.asset.resolve()
    data = validateAsset(assetPath)

    apiBase = f"https://api.github.com/repos/{repository}/releases"
    try:
        release = requestJson(f"{apiBase}/tags/{quote(releaseTag)}", token)
    except HTTPError as error:
        if error.code != 404:
            raise
        release = requestJson(apiBase, token, "POST", {
            "tag_name": releaseTag,
            "target_commitish": commit,
            "name": "C/C++ Support 0.1.0",
            "body": (
                "First-party C/C++ Support for Kinetic 0.22.0. Adds C/C++ syntax tokens, "
                "clangd diagnostics and Go to Definition, explicit clang-format formatting, "
                "and header/source switching. The plugin uses installed toolchains and does "
                "not download tools automatically."
            ),
            "draft": False,
            "prerelease": True,
        })

    if any(asset["name"] == assetName for asset in release.get("assets", [])):
        raise ValueError("The release already has this immutable asset; refusing to replace it")
    uploadUrl = release["upload_url"].split("{", 1)[0]
    expectedPrefix = f"https://uploads.github.com/repos/{repository}/releases/"
    if not uploadUrl.startswith(expectedPrefix):
        raise ValueError("Unexpected GitHub release upload URL")
    request = Request(f"{uploadUrl}?name={quote(assetName)}", data=data, method="POST", headers={
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/octet-stream",
        "User-Agent": "Kinetic-Official-Plugin-Publisher",
    })
    with urlopen(request, timeout=120) as response:
        uploaded = json.load(response)
    if uploaded.get("name") != assetName or uploaded.get("size") != len(data):
        raise ValueError("GitHub reported an unexpected uploaded asset")
    print(f"Release: {release['html_url']}")
    print(f"Asset: {uploaded['browser_download_url']}")
    print(f"Size: {len(data)}")
    print(f"SHA-256: {hashlib.sha256(data).hexdigest()}")


if __name__ == "__main__":
    try:
        main()
    except (HTTPError, OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"Plugin publication failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
