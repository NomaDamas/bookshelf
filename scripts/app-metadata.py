"""Manage product metadata and generate the app's Info.plist (Python stdlib only)."""

import argparse
import json
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources/BookshelfCore/Resources/AppMetadata.json"
PLIST = ROOT / "Resources/Info.plist"


def metadata():
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", data["version"]):
        raise ValueError("version must be a numeric MAJOR.MINOR.PATCH without a v prefix")
    if type(data["buildNumber"]) is not int or data["buildNumber"] < 1:
        raise ValueError("buildNumber must be a positive integer")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z0-9-]+)+", data["bundleIdentifier"]):
        raise ValueError("bundleIdentifier must be a reverse-DNS identifier")
    major = data["minimumMacOS"].split(".")[0]
    if f".macOS(.v{major})" not in (ROOT / "Package.swift").read_text():
        raise ValueError("minimumMacOS must agree with Package.swift")
    return data


def plist_bytes(data):
    result = {
        # The interface is Korean, so AppKit's own menu items (파일, 편집, 실행 취소) must be Korean too.
        "CFBundleDevelopmentRegion": "ko",
        "CFBundleLocalizations": ["ko"],
        "CFBundleExecutable": "Bookside",
        "CFBundleIdentifier": data["bundleIdentifier"],
        "CFBundleName": data["name"],
        "CFBundleDisplayName": data["name"],
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": data["version"],
        "CFBundleVersion": str(data["buildNumber"]),
        "CFBundleIconFile": "AppIcon",
        "LSMinimumSystemVersion": data["minimumMacOS"],
        "NSHighResolutionCapable": True,
        "NSPrincipalClass": "NSApplication",
        "NSHumanReadableCopyright": "Bookside contributors. MIT License.",
        "CFBundleURLTypes": [{
            "CFBundleURLName": data["bundleIdentifier"] + ".book",
            # bookshelf:// links written before the rename keep opening books.
            "CFBundleURLSchemes": ["bookside", "bookshelf"],
        }],
    }
    return plistlib.dumps(result, sort_keys=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("check", "generate", "version"):
        sub.add_parser(name)
    setter = sub.add_parser("set", help="Set a newer version and increment the build number")
    setter.add_argument("version")
    args = parser.parse_args()
    data = metadata()
    if args.command == "set":
        if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", args.version):
            parser.error("Use a numeric MAJOR.MINOR.PATCH")
        if tuple(map(int, args.version.split("."))) <= tuple(map(int, data["version"].split("."))):
            parser.error("The new version must be greater than the current version")
        data["version"] = args.version
        data["buildNumber"] += 1
        SOURCE.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    if args.command in ("generate", "set"):
        PLIST.write_bytes(plist_bytes(data))
        print(f"Generated {PLIST.relative_to(ROOT)} for {data['version']} ({data['buildNumber']})")
    elif args.command == "check":
        if not PLIST.exists() or PLIST.read_bytes() != plist_bytes(data):
            raise SystemExit("Info.plist is stale. Run: python3 scripts/app-metadata.py generate")
        print("Product metadata and Info.plist agree.")
    else:
        print(data["version"])


if __name__ == "__main__":
    main()
