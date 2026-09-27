#!/usr/bin/env python3
"""Build and validate Kinetic's GitHub-hosted native plugin catalog."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import sys
from urllib.parse import unquote, urlsplit
from urllib.request import Request, urlopen


rootPath = Path(__file__).resolve().parent.parent
maximumAssetBytes = 32 * 1024 * 1024
entryKeys = {"schemaVersion", "id", "name", "summary", "publisher", "version",
             "apiVersion", "platform", "asset"}
publisherKeys = {"githubId", "githubLogin"}
assetKeys = {"url", "sha256", "sizeBytes"}
idPattern = re.compile(r"[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*\Z")
versionPattern = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")
loginPattern = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})\Z")
shaPattern = re.compile(r"[0-9a-f]{64}\Z")


class RegistryError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise RegistryError(message)


def readJson(path):
    require(not path.is_symlink() and not path.parent.is_symlink(),
            f"Symlinks are not accepted: {path}")
    require(path.is_file() and path.stat().st_size <= 16384,
            f"Missing or oversized JSON file: {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise RegistryError(f"Invalid JSON in {path}: {error}") from error


def canonicalJson(value):
    return (json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8")


def validVersion(version):
    match = versionPattern.fullmatch(version) if isinstance(version, str) else None
    require(match is not None, f"Invalid main.feature.patch version: {version}")
    numbers = tuple(int(part) for part in match.groups())
    require(numbers[1] <= 99 and numbers[2] <= 99, f"Version component exceeds 99: {version}")
    return numbers


def validReleaseUrl(url, publisherLogin):
    require(isinstance(url, str), "Asset URL must be a string")
    parts = urlsplit(url)
    require(parts.scheme == "https" and parts.netloc == "github.com" and
            not parts.query and not parts.fragment, "Asset URL must be an HTTPS GitHub release URL")
    segments = [unquote(part) for part in parts.path.split("/")]
    require(len(segments) == 7 and segments[0] == "" and
            segments[3:5] == ["releases", "download"] and
            all(part and part not in (".", "..") and "/" not in part and "\\" not in part
                for part in segments[1:]), "Asset URL must identify one GitHub release asset")
    require(segments[1].lower() == publisherLogin.lower(),
            "Release repository owner must match the publisher login")
    require(loginPattern.fullmatch(segments[1]) is not None and
            re.fullmatch(r"[A-Za-z0-9._-]{1,100}", segments[2]) is not None,
            "Invalid release repository")
    require(segments[6].endswith(".dylib") and len(segments[6]) <= 128,
            "Release asset must be a .dylib")
    return segments[6]


def validMachO(data):
    return len(data) >= 16 and data[:4] == b"\xcf\xfa\xed\xfe" and \
        struct.unpack_from("<I", data, 4)[0] == 0x0100000C and \
        struct.unpack_from("<I", data, 12)[0] in (6, 8)


def validateEntry(entry, path=None):
    require(isinstance(entry, dict) and set(entry) == entryKeys,
            "Release entry has missing or unsupported fields")
    require(type(entry["schemaVersion"]) is int and entry["schemaVersion"] == 1,
            "Release entry schemaVersion must be 1")
    pluginId = entry["id"]
    require(isinstance(pluginId, str) and len(pluginId) <= 96 and
            idPattern.fullmatch(pluginId) is not None, "Invalid plugin ID")
    validVersion(entry["version"])
    require(isinstance(entry["name"], str) and 1 <= len(entry["name"]) <= 80,
            "Plugin name must be 1-80 characters")
    require(isinstance(entry["summary"], str) and 1 <= len(entry["summary"]) <= 240,
            "Plugin summary must be 1-240 characters")
    require(type(entry["apiVersion"]) is int and entry["apiVersion"] == 1,
            "Only plugin ABI version 1 is supported")
    require(entry["platform"] == "macos-arm64", "Only macos-arm64 is supported")
    publisher = entry["publisher"]
    require(isinstance(publisher, dict) and set(publisher) == publisherKeys,
            "Publisher must contain githubId and githubLogin")
    require(type(publisher["githubId"]) is int and publisher["githubId"] > 0,
            "Publisher githubId must be a positive GitHub user ID")
    require(isinstance(publisher["githubLogin"], str) and
            loginPattern.fullmatch(publisher["githubLogin"]) is not None,
            "Invalid GitHub publisher login")
    asset = entry["asset"]
    require(isinstance(asset, dict) and set(asset) == assetKeys,
            "Asset must contain url, sha256, and sizeBytes")
    validReleaseUrl(asset["url"], publisher["githubLogin"])
    require(isinstance(asset["sha256"], str) and shaPattern.fullmatch(asset["sha256"]) is not None,
            "Asset SHA-256 must be 64 lowercase hex characters")
    require(type(asset["sizeBytes"]) is int and 16 <= asset["sizeBytes"] <= maximumAssetBytes,
            "Asset size is invalid or exceeds 32 MiB")
    if path is not None:
        require(path.parent.name == pluginId and path.name == entry["version"] + ".json",
                f"Entry path must be entries/{pluginId}/{entry['version']}.json")
    return entry


def loadOfficial(root):
    policy = readJson(root / "registry" / "official.json")
    require(isinstance(policy, dict) and set(policy) == {"schemaVersion", "plugins"} and
            policy["schemaVersion"] == 1 and isinstance(policy["plugins"], dict),
            "Invalid Official policy")
    for pluginId, githubId in policy["plugins"].items():
        require(isinstance(pluginId, str) and idPattern.fullmatch(pluginId) is not None and
                type(githubId) is int and githubId > 0, "Invalid Official policy entry")
    return policy["plugins"]


def loadEntries(root):
    entryRoot = root / "registry" / "entries"
    require(entryRoot.is_dir() and not entryRoot.is_symlink(), "Missing registry/entries")
    entries = []
    for path in sorted(entryRoot.glob("*/*.json")):
        entries.append(validateEntry(readJson(path), path))
    return entries


def buildIndex(root):
    official = loadOfficial(root)
    grouped = {}
    for entry in loadEntries(root):
        pluginId = entry["id"]
        publisher = entry["publisher"]
        require(not pluginId.startswith("kinetic.") or pluginId in official,
                "The kinetic.* namespace is reserved for Official plugins")
        if pluginId in grouped:
            previous = grouped[pluginId]
            require(previous["publisher"]["githubId"] == publisher["githubId"],
                    f"Publisher ownership changed for {pluginId}")
            require(previous["name"] == entry["name"],
                    f"Plugin name changed between releases for {pluginId}")
        else:
            grouped[pluginId] = {
                "id": pluginId,
                "name": entry["name"],
                "summary": entry["summary"],
                "publisher": publisher,
                "official": pluginId in official,
                "releases": [],
            }
        grouped[pluginId]["releases"].append({
            "version": entry["version"],
            "apiVersion": entry["apiVersion"],
            "platform": entry["platform"],
            "asset": entry["asset"],
        })
    for pluginId, githubId in official.items():
        require(pluginId in grouped and grouped[pluginId]["publisher"]["githubId"] == githubId,
                f"Official publisher mismatch or missing plugin: {pluginId}")
    for plugin in grouped.values():
        plugin["releases"].sort(key=lambda release: validVersion(release["version"]), reverse=True)
    return {"schemaVersion": 1, "plugins": [grouped[key] for key in sorted(grouped)]}


def checkIndex(root):
    expected = canonicalJson(buildIndex(root))
    indexPath = root / "registry" / "index.json"
    require(indexPath.is_file() and indexPath.read_bytes() == expected,
            "registry/index.json is stale; run the build command")


def draftEntry(root, options):
    assetPath = Path(options.asset).resolve()
    require(assetPath.is_file() and not assetPath.is_symlink(), "Asset must be a regular file")
    require(16 <= assetPath.stat().st_size <= maximumAssetBytes,
            "Asset must be between 16 bytes and 32 MiB")
    data = assetPath.read_bytes()
    require(validMachO(data), "Asset must be an arm64 Mach-O dynamic library")
    releaseName = validReleaseUrl(options.releaseUrl, options.githubLogin)
    require(releaseName == assetPath.name, "Release URL asset name must match the local file")
    entry = {
        "schemaVersion": 1,
        "id": options.pluginId,
        "name": options.name,
        "summary": options.summary,
        "publisher": {"githubId": options.githubId, "githubLogin": options.githubLogin},
        "version": options.version,
        "apiVersion": 1,
        "platform": "macos-arm64",
        "asset": {
            "url": options.releaseUrl,
            "sha256": hashlib.sha256(data).hexdigest(),
            "sizeBytes": len(data),
        },
    }
    validateEntry(entry)
    entryPath = root / "registry" / "entries" / entry["id"] / (entry["version"] + ".json")
    require(not entryPath.exists(), f"Release entry already exists: {entryPath}")
    entryPath.parent.mkdir(parents=True, exist_ok=True)
    entryPath.write_bytes(canonicalJson(entry))
    try:
        index = buildIndex(root)
    except RegistryError:
        entryPath.unlink()
        raise
    (root / "registry" / "index.json").write_bytes(canonicalJson(index))
    return entryPath


def downloadAsset(url):
    request = Request(url, headers={"User-Agent": "Kinetic-Plugin-Registry"})
    with urlopen(request, timeout=30) as response:
        if response.headers.get("Content-Length"):
            require(int(response.headers["Content-Length"]) <= maximumAssetBytes,
                    "Release asset exceeds 32 MiB")
        data = response.read(maximumAssetBytes + 1)
    require(len(data) <= maximumAssetBytes, "Release asset exceeds 32 MiB")
    return data


def verifyAssets(entries, downloader=downloadAsset):
    for entry in entries:
        data = downloader(entry["asset"]["url"])
        require(validMachO(data), f"Release asset is not arm64 Mach-O: {entry['id']}")
        require(len(data) == entry["asset"]["sizeBytes"] and
                hashlib.sha256(data).hexdigest() == entry["asset"]["sha256"],
                f"Release asset checksum mismatch: {entry['id']} {entry['version']}")


def validateChangedFiles(root, changedFiles, author, owner):
    for changed in changedFiles:
        name = changed["filename"]
        if name == "registry/official.json":
            require(author["id"] == owner["id"],
                    "Only the repository owner may change Official policy")
        if name.startswith("registry/entries/") and name.endswith(".json"):
            require(changed["status"] == "added", "Published releases are immutable")
            entry = validateEntry(readJson(root / name))
            require(entry["publisher"]["githubId"] == author["id"] and
                    entry["publisher"]["githubLogin"].lower() == author["login"].lower(),
                    "PR author must match the release publisher GitHub identity")


def checkPr(root, eventPath):
    eventFile = Path(eventPath)
    require(eventFile.is_file() and eventFile.stat().st_size <= 1024 * 1024,
            "GitHub pull request event is missing or oversized")
    event = json.loads(eventFile.read_text(encoding="utf-8"))
    request = event.get("pull_request")
    repository = event.get("repository")
    require(isinstance(request, dict) and isinstance(repository, dict),
            "A GitHub pull_request event is required")
    author = request["user"]
    owner = repository["owner"]
    token = os.environ.get("GITHUB_TOKEN")
    require(token, "GITHUB_TOKEN is required to inspect changed PR files")
    apiUrl = f"https://api.github.com/repos/{repository['full_name']}/pulls/{request['number']}/files"
    page = 1
    while True:
        apiRequest = Request(f"{apiUrl}?per_page=100&page={page}", headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "User-Agent": "Kinetic-Plugin-Registry",
        })
        with urlopen(apiRequest, timeout=30) as response:
            changedFiles = json.load(response)
        require(isinstance(changedFiles, list), "Invalid GitHub pull request file list")
        validateChangedFiles(root, changedFiles, author, owner)
        if len(changedFiles) < 100:
            break
        page += 1
        require(page <= 10, "Pull request changes exceed registry review limit")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=rootPath)
    commands = parser.add_subparsers(dest="command", required=True)
    draft = commands.add_parser("draft", help="create a release entry and update the index")
    draft.add_argument("--id", dest="pluginId", required=True)
    draft.add_argument("--name", required=True)
    draft.add_argument("--summary", required=True)
    draft.add_argument("--github-login", dest="githubLogin", required=True)
    draft.add_argument("--github-id", dest="githubId", required=True, type=int)
    draft.add_argument("--version", required=True)
    draft.add_argument("--asset", required=True)
    draft.add_argument("--release-url", dest="releaseUrl", required=True)
    commands.add_parser("check", help="validate entries and the checked-in index")
    build = commands.add_parser("build", help="write a deterministic public index")
    build.add_argument("--output", required=True, type=Path)
    commands.add_parser("verify-assets", help="download public release assets and verify hashes")
    pullRequest = commands.add_parser("check-pr", help="verify changed release ownership")
    pullRequest.add_argument("--event", required=True)
    options = parser.parse_args()
    root = options.root.resolve()
    try:
        if options.command == "draft":
            print(draftEntry(root, options))
        elif options.command == "check":
            checkIndex(root)
            print("Plugin registry is valid")
        elif options.command == "build":
            options.output.parent.mkdir(parents=True, exist_ok=True)
            options.output.write_bytes(canonicalJson(buildIndex(root)))
        elif options.command == "verify-assets":
            verifyAssets(loadEntries(root))
            print("Release asset checksums match")
        elif options.command == "check-pr":
            checkPr(root, options.event)
            print("Pull request publisher identity matches")
    except (RegistryError, OSError, ValueError) as error:
        print(f"Plugin registry error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
