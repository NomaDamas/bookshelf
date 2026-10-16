"""Build, package, and verify Bookshelf macOS distribution artifacts."""

import argparse
import hashlib
import json
import os
import platform
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "dist/Bookshelf.app"
METADATA = ROOT / "Sources/BookshelfCore/Resources/AppMetadata.json"


def run(*args, capture=False, env=None):
    return subprocess.run(
        [str(a) for a in args], check=True, cwd=ROOT,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        env=env,
    ).stdout


def product():
    return json.loads(METADATA.read_text(encoding="utf-8"))


def identity():
    value = os.environ.get("BOOKSHELF_SIGNING_IDENTITY", "-")
    if value != "-" and not value.startswith("Developer ID Application:"):
        raise ValueError("Use a Developer ID Application identity, or '-' for an ad-hoc local build")
    return value


def sign_app(bundle):
    signing = identity()
    flags = ["--force", "--sign", signing]
    if signing != "-":
        flags += ["--options", "runtime", "--timestamp"]
    for binary in ("bookshelf-cli", "Bookshelf"):
        run("codesign", *flags, bundle / "Contents/MacOS" / binary)
    run("codesign", *flags, bundle)
    run("codesign", "--verify", "--deep", "--strict", bundle)
    print("Signature verified:", "ad-hoc" if signing == "-" else "Developer ID")


def validate_tag(tag):
    run("python3", ROOT / "scripts/app-metadata.py", "check")
    expected = "v" + product()["version"]
    if tag != expected:
        raise ValueError(f"Tag must match product metadata: expected {expected}, got {tag}")
    if run("git", "status", "--porcelain", capture=True).strip():
        raise ValueError("A release tag requires a clean checkout")
    tag_sha = run("git", "rev-parse", f"refs/tags/{tag}^{{commit}}", capture=True).strip()
    head = run("git", "rev-parse", "HEAD", capture=True).strip()
    if tag_sha != head:
        raise ValueError("Check out the exact tagged commit before releasing")
    run("git", "merge-base", "--is-ancestor", head.decode(), "origin/main")
    print(f"Release tag verified: {tag} at {head.decode()}")


def verify_bundle(bundle, expected_arch=None):
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    run("codesign", "--verify", "--deep", "--strict", bundle)
    architectures = {}
    for binary in ("Bookshelf", "bookshelf-cli"):
        architectures[binary] = run("lipo", "-archs", bundle / "Contents/MacOS" / binary, capture=True).decode().split()
        if expected_arch and expected_arch not in architectures[binary]:
            raise ValueError(f"{binary} does not contain expected architecture {expected_arch}")
    with tempfile.TemporaryDirectory(prefix="bookshelf-verify-") as temporary:
        env = {**os.environ, "BOOKSHELF_DATA_DIR": str(Path(temporary) / "data")}
        cli = bundle / "Contents/MacOS/bookshelf-cli"
        version = run(cli, "--version", capture=True, env=env).decode().strip()
        expected = f"{info['CFBundleName']} {info['CFBundleShortVersionString']} (build {info['CFBundleVersion']})"
        if version != expected:
            raise ValueError(f"CLI/plist version mismatch: {version} != {expected}")
        doctor = json.loads(run(cli, "doctor", capture=True, env=env))
        if doctor["bundle_identifier"] != info["CFBundleIdentifier"]:
            raise ValueError("CLI/plist bundle identifier mismatch")
        if doctor["version"] != info["CFBundleShortVersionString"] or str(doctor["build_number"]) != info["CFBundleVersion"]:
            raise ValueError("Runtime metadata does not match the packaged app")
    if not (bundle / "Contents/Resources/ThirdParty").is_dir():
        raise ValueError("Dependency notices are missing")
    return {"version": info["CFBundleShortVersionString"], "buildNumber": info["CFBundleVersion"],
            "bundleIdentifier": info["CFBundleIdentifier"], "architectures": architectures}


def verify_dmg(dmg, expected_arch=None):
    run("hdiutil", "verify", dmg)
    with tempfile.TemporaryDirectory(prefix="bookshelf-dmg-check-") as temporary:
        mount = Path(temporary) / "volume"
        mount.mkdir()
        attached = False
        try:
            run("hdiutil", "attach", dmg, "-readonly", "-nobrowse", "-mountpoint", mount, capture=True)
            attached = True
            if not (mount / "Applications").is_symlink() or os.readlink(mount / "Applications") != "/Applications":
                raise ValueError("DMG must contain the Applications shortcut")
            # Exercise the same bundle a user copies off the mounted disk image.
            installed = Path(temporary) / "Installed/Bookshelf.app"
            installed.parent.mkdir()
            run("ditto", mount / "Bookshelf.app", installed)
            result = verify_bundle(installed, expected_arch)
            print(json.dumps({"dmg": dmg.name, "copied_app_verified": True, **result}, indent=2))
            return result
        finally:
            if attached:
                run("hdiutil", "detach", mount)


def package(output, skip_build=False, notarize=False):
    run("python3", ROOT / "scripts/app-metadata.py", "check")
    signing = identity()
    profile = os.environ.get("BOOKSHELF_NOTARY_PROFILE")
    if notarize and (signing == "-" or not profile):
        raise ValueError("Notarization requires Developer ID signing and BOOKSHELF_NOTARY_PROFILE")
    if not skip_build:
        run(ROOT / "scripts/build-app.sh", env={**os.environ, "BOOKSHELF_BUILD_CONFIGURATION": "release"})
    data = product()
    arch = platform.machine()
    if arch not in ("arm64", "x86_64"):
        raise ValueError(f"Unsupported release architecture: {arch}")
    checked = verify_bundle(APP, arch)
    info = plistlib.loads((APP / "Contents/Info.plist").read_bytes())
    if checked["version"] != data["version"] or checked["bundleIdentifier"] != data["bundleIdentifier"]:
        raise ValueError("The app is stale; rebuild it before packaging")
    if info.get("BookshelfBuildConfiguration") != "release":
        raise ValueError("Distribution requires a release build")
    revision = run("git", "rev-parse", "HEAD", capture=True).decode().strip()
    if info.get("BookshelfSourceRevision") != revision:
        raise ValueError("The app was built from another commit; rebuild it")
    signature = subprocess.run(["codesign", "-d", "--verbose=4", str(APP)], capture_output=True, check=True).stderr.decode()
    signed = "Authority=Developer ID Application:" in signature
    if signed != (signing != "-"):
        raise ValueError("Bundle signature differs from the requested signing mode; rebuild it")
    stem = f"Bookshelf-{data['version']}-macos-{arch}"
    output.mkdir(parents=True, exist_ok=True)
    dmg = output / (stem + ".dmg")
    record = output / (stem + ".json")
    checksum = output / (stem + ".dmg.sha256")
    if any(p.exists() for p in (dmg, record, checksum)):
        raise ValueError("Release outputs already exist; choose a fresh --output directory")
    with tempfile.TemporaryDirectory(prefix="bookshelf-package-") as temporary:
        stage = Path(temporary) / "image"
        stage.mkdir()
        run("ditto", APP, stage / "Bookshelf.app")
        (stage / "Applications").symlink_to("/Applications")
        shutil.copy2(ROOT / "LICENSE", stage / "LICENSE.txt")
        warning = "Developer ID signed; see release notes for notarization status." if signed else "Ad-hoc signed developer preview. Not notarized by Apple."
        (stage / "READ ME.txt").write_text(
            f"Bookshelf {data['version']}\n\nDrag Bookshelf.app to Applications.\n"
            "Quit the old app before replacing it. Your library and notes remain in Application Support/Bookshelf.\n\n"
            + warning + "\nOCR dependencies are installed separately.\n"
            + data["repository"] + "/blob/main/docs/01-getting-started.md\n", encoding="utf-8")
        run("hdiutil", "create", "-volname", f"Bookshelf {data['version']}", "-srcfolder", stage,
            "-format", "UDZO", "-fs", "HFS+", dmg)
    if signed:
        run("codesign", "--sign", signing, "--timestamp", dmg)
    if notarize:
        run("xcrun", "notarytool", "submit", dmg, "--keychain-profile", profile, "--wait")
        run("xcrun", "stapler", "staple", dmg)
        run("xcrun", "stapler", "validate", dmg)
    verify_dmg(dmg, arch)
    checksum.write_text(hashlib.sha256(dmg.read_bytes()).hexdigest() + "  " + dmg.name + "\n", encoding="utf-8")
    record.write_text(json.dumps({
        **data, "architecture": arch, "sourceRevision": revision,
        "sourceDirty": info.get("BookshelfSourceDirty", True),
        "signing": "developer-id" if signed else "ad-hoc", "notarized": notarize,
        "artifact": dmg.name, "sha256": hashlib.sha256(dmg.read_bytes()).hexdigest(),
    }, indent=2) + "\n", encoding="utf-8")
    print(f"Verified release artifacts: {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sign = sub.add_parser("sign-app")
    sign.add_argument("bundle", type=Path)
    pack = sub.add_parser("package")
    pack.add_argument("--output", type=Path, default=ROOT / "dist/release")
    pack.add_argument("--skip-build", action="store_true")
    pack.add_argument("--notarize", action="store_true")
    verify = sub.add_parser("verify")
    verify.add_argument("dmg", type=Path)
    verify.add_argument("--arch", choices=["arm64", "x86_64"])
    tag = sub.add_parser("validate-tag")
    tag.add_argument("tag")
    args = parser.parse_args()
    if args.command == "validate-tag":
        validate_tag(args.tag)
        return
    if platform.system() != "Darwin":
        parser.error("App signing, packaging, and verification require macOS")
    if args.command == "sign-app":
        sign_app(args.bundle.resolve())
    elif args.command == "package":
        package(args.output.resolve(), args.skip_build, args.notarize)
    else:
        verify_dmg(args.dmg.resolve(), args.arch)


if __name__ == "__main__":
    main()
