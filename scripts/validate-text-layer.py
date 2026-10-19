"""Validate a spacing-only PDF repair: all page text, geometry, image bytes and selected rendered pages."""

import argparse
import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path

import pikepdf
from PIL import Image


def image_fingerprints(pdf):
    result = []
    for obj in pdf.objects:
        if isinstance(obj, pikepdf.Stream) and obj.get("/Subtype") == "/Image":
            result.append(
                (
                    int(obj.get("/Width", 0)),
                    int(obj.get("/Height", 0)),
                    hashlib.sha256(obj.read_raw_bytes()).hexdigest(),
                )
            )
    return sorted(result)


def probe(binary, pdf):
    result = subprocess.run(
        [str(binary), str(pdf), "all"],
        check=True,
        text=True,
        capture_output=True,
        timeout=300,
    )
    return json.loads(result.stdout)


def file_digest(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def spaced_korean(text):
    runs = re.findall(r"[가-힣]+", text)
    count = sum(map(len, runs))
    return (
        count >= 80
        and count / len(runs) < 1.45
        and sum(len(s) == 1 for s in runs) / len(runs) > 0.65
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("repaired", type=Path)
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--render-pages", default="")
    args = parser.parse_args()
    old, new = probe(args.probe, args.original), probe(args.probe, args.repaired)
    old_poppler = subprocess.run(
        ["pdftotext", str(args.original), "-"],
        check=True,
        text=True,
        capture_output=True,
        timeout=300,
    ).stdout.split("\f")
    new_poppler = subprocess.run(
        ["pdftotext", str(args.repaired), "-"],
        check=True,
        text=True,
        capture_output=True,
        timeout=300,
    ).stdout.split("\f")
    failures = []
    if old["page_count"] != new["page_count"]:
        failures.append("page count")
    changed_spacing, changed_characters, changed_geometry = [], [], []
    poppler_changes = []
    original_spaced, residual_spaced = [], []
    for a, b in zip(old["pages"], new["pages"]):
        if (a["width"], a["height"], a["rotation"]) != (
            b["width"],
            b["height"],
            b["rotation"],
        ):
            changed_geometry.append(a["page"])
        if re.sub(r"\s+", "", a["text"]) != re.sub(r"\s+", "", b["text"]):
            changed_characters.append(a["page"])
        elif a["text"] != b["text"]:
            changed_spacing.append(a["page"])
        if spaced_korean(a["text"]):
            original_spaced.append(a["page"])
            if spaced_korean(b["text"]):
                residual_spaced.append(a["page"])
    if changed_geometry:
        failures.append("page geometry")
    for index in range(old["page_count"]):
        if (
            index >= len(old_poppler)
            or index >= len(new_poppler)
            or re.sub(r"\s+", "", old_poppler[index])
            != re.sub(r"\s+", "", new_poppler[index])
        ):
            poppler_changes.append(index + 1)
    if changed_characters or poppler_changes:
        failures.append("non-whitespace text")
    with pikepdf.open(args.original) as a, pikepdf.open(args.repaired) as b:
        old_images, new_images = image_fingerprints(a), image_fingerprints(b)
        if old_images != new_images:
            failures.append("image bytes")
    rendered = []
    with tempfile.TemporaryDirectory(prefix="bookside-layer-validation-") as temporary:
        for number in filter(None, args.render_pages.split(",")):
            pixels = []
            for index, source in enumerate([args.original, args.repaired]):
                output = Path(temporary) / f"{number}-{index}"
                subprocess.run(
                    [
                        "pdftoppm",
                        "-f",
                        number,
                        "-l",
                        number,
                        "-r",
                        "72",
                        "-singlefile",
                        "-png",
                        str(source),
                        str(output),
                    ],
                    check=True,
                    capture_output=True,
                    timeout=60,
                )
                with Image.open(str(output) + ".png") as image:
                    pixels.append(
                        (
                            image.size,
                            hashlib.sha256(image.convert("RGB").tobytes()).hexdigest(),
                        )
                    )
            rendered.append(
                {"page": int(number), "pixels_identical": pixels[0] == pixels[1]}
            )
    if any(not row["pixels_identical"] for row in rendered):
        failures.append("rendered pixels")
    result = {
        "passed": not failures,
        "failures": failures,
        "page_count": old["page_count"],
        "changed_spacing_pages": changed_spacing,
        "changed_character_pages": sorted(set(changed_characters + poppler_changes)),
        "pdfkit_changed_character_pages": changed_characters,
        "poppler_changed_character_pages": poppler_changes,
        "changed_geometry_pages": changed_geometry,
        "images_identical": old_images == new_images,
        "original_spaced_pages": original_spaced,
        "residual_spaced_pages": residual_spaced,
        "image_count": len(old_images),
        "rendered": rendered,
        "original_sha256": file_digest(args.original),
        "repaired_sha256": file_digest(args.repaired),
    }
    args.report.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
