#!/usr/bin/env python3
"""Bundle redistributable LLVM tools and their non-system Mach-O dependencies."""

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def dependencies(path):
    return [line.strip().split(" (compatibility", 1)[0]
            for line in run("xcrun", "otool", "-L", str(path)).splitlines()[1:]]


def rpaths(path):
    return re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset",
                      run("xcrun", "otool", "-l", str(path)))


def copyResource(source, destination):
    destination = Path(destination)
    if destination.exists():
        destination.chmod(0o644)
    shutil.copyfile(source, destination)
    destination.chmod(0o644)
    return str(destination)


def resolve(name, source, root):
    if name.startswith("@loader_path/"):
        return (source.parent / name.removeprefix("@loader_path/")).resolve(strict=True)
    if name.startswith("@rpath/"):
        suffix = name.removeprefix("@rpath/")
        for entry in [*rpaths(source), str(root / "lib")]:
            directory = Path(entry.replace("@loader_path", str(source.parent)))
            candidate = directory / suffix
            if candidate.is_file():
                return candidate.resolve()
        raise RuntimeError(f"Cannot resolve dependency {name}")
    return Path(name).resolve(strict=True)


def bundle(root, app, minimum, allowNewer):
    root = root.resolve(strict=True)
    target = app / "Contents/Resources/tools/llvm"
    licenses = target / "licenses"
    licenses.mkdir(parents=True, exist_ok=True)
    copied = {}
    names = {}
    notices = set()

    def copyLicense(source):
        prefix = source.parent.parent
        if prefix in notices:
            return
        files = [prefix / name for name in ("LICENSE.TXT", "LICENSE", "COPYING", "NOTICE")]
        files = [path for path in files if path.is_file()]
        if not files:
            raise RuntimeError(f"No redistribution license found for {source.name}")
        label = "llvm" if prefix == root else prefix.parent.name
        destination = licenses / label
        destination.mkdir(exist_ok=True)
        for path in files:
            shutil.copyfile(path, destination / path.name)
        notices.add(prefix)

    def copyBinary(source, destination):
        source = source.resolve(strict=True)
        if source in copied:
            return copied[source]
        if destination.name in names and names[destination.name] != source:
            raise RuntimeError(f"Conflicting dependency name: {destination.name}")
        if "arm64" not in run("xcrun", "lipo", "-archs", str(source)).split():
            raise RuntimeError(f"Missing arm64 slice: {source.name}")
        buildInfo = run("xcrun", "otool", "-arch", "arm64", "-l", str(source))
        versions = re.findall(r"\bminos\s+([\d.]+)", buildInfo)
        if not versions:
            raise RuntimeError(f"Cannot verify minimum macOS version: {source.name}")
        newest = max(tuple(int(part) for part in version.split(".")) for version in versions)
        required = tuple(int(part) for part in minimum.split("."))
        if newest > required:
            message = f"{source.name} requires macOS {'.'.join(map(str, newest))}; target is {minimum}"
            if not allowNewer:
                raise RuntimeError(message)
            print(f"Development-only LLVM bundle: {message}")
        copyLicense(source)
        names[destination.name] = source
        copied[source] = destination
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        destination.chmod(0o755)
        for name in dependencies(source):
            if name.startswith(("/usr/lib/", "/System/Library/")):
                continue
            dependency = resolve(name, source, root)
            if dependency == source:
                continue
            bundled = copyBinary(dependency, target / "lib" / Path(name).name)
            replacement = ("@loader_path/../lib/" if destination.parent.name == "bin"
                           else "@loader_path/") + bundled.name
            subprocess.run(["xcrun", "install_name_tool", "-change", name, replacement,
                            str(destination)], check=True, capture_output=True)
        if destination.parent.name == "lib":
            subprocess.run(["xcrun", "install_name_tool", "-id", "@rpath/" + destination.name,
                            str(destination)], check=True, capture_output=True)
        # Resolved dependencies use loader-relative paths, so host rpaths are unnecessary.
        for entry in rpaths(destination):
            subprocess.run(["xcrun", "install_name_tool", "-delete_rpath", entry,
                            str(destination)], check=True, capture_output=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(destination)],
                       check=True, capture_output=True)
        return destination

    for name in ("clangd", "clang-format"):
        copyBinary(root / "bin" / name, target / "bin" / name)
    versions = sorted((root / "lib/clang").iterdir(), key=lambda path: tuple(
        int(piece) for piece in path.name.split(".") if piece.isdigit()))
    resource = next((path for path in reversed(versions) if (path / "include").is_dir()), None)
    if resource is None:
        raise RuntimeError("LLVM resource headers are missing")
    shutil.copytree(resource / "include", target / "lib/clang" / resource.name / "include",
                    dirs_exist_ok=True, copy_function=copyResource)
    manifest = {"resourceVersion": resource.name, "tools": {name: run(
        str(target / "bin" / name), "--version").splitlines()[0]
        for name in ("clangd", "clang-format")}}
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    for destination in copied.values():
        for name in dependencies(destination):
            if not name.startswith(("/usr/lib/", "/System/Library/", "@loader_path/", "@rpath/")):
                raise RuntimeError(f"Non-portable dependency in {destination.name}: {name}")
    print("Bundled clangd, clang-format, runtime libraries, headers, and licenses")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--llvm-root", type=Path, required=True)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--minimum-macos", default="15.0")
    parser.add_argument("--allow-newer-for-development", action="store_true")
    args = parser.parse_args()
    bundle(args.llvm_root, args.app, args.minimum_macos, args.allow_newer_for_development)
