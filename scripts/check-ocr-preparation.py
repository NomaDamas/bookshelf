"""Check nested OCR removal without changing visible text, vectors, images or mixed text blocks.

Run in the OCRmyPDF Python environment, which supplies pikepdf. Uses synthetic PDFs only.
"""

import hashlib
import subprocess
import sys
import tempfile
from pathlib import Path

import pikepdf

root = Path(__file__).resolve().parents[1]
helper = root / "Sources/BookshelfCore/Resources/prepare-ocr-replacement.py"
with tempfile.TemporaryDirectory(prefix="bookshelf-preparation-") as temporary:
    folder = Path(temporary)
    source, output = folder / "source.pdf", folder / "prepared.pdf"
    with pikepdf.Pdf.new() as pdf:
        page = pdf.add_blank_page(page_size=(400, 400))
        font = pdf.make_indirect(
            pikepdf.Dictionary(
                Type=pikepdf.Name.Font,
                Subtype=pikepdf.Name.Type1,
                BaseFont=pikepdf.Name.Helvetica,
            )
        )
        child = pdf.make_stream(
            b"q BT /F1 16 Tf 0 Tr 1 0 0 1 20 330 Tm (VISIBLE_HEADER) Tj ET Q\nq BT /F1 16 Tf 3 Tr 1 0 0 1 20 300 Tm /Span << /ActualText (HIDDEN_MARKER) >> BDC (HIDDEN_MARKER) Tj EMC ET Q\n1 0 0 RG 2 w 20 250 m 350 250 l S\nBT /F1 14 Tf 0 Tr 1 0 0 1 20 200 Tm (MIXED_VISIBLE) Tj 3 Tr (MIXED_HIDDEN) Tj 0 Tr (VISIBLE_TAIL) Tj ET"
        )
        child.Type = pikepdf.Name.XObject
        child.Subtype = pikepdf.Name.Form
        child.BBox = [0, 0, 400, 400]
        child.Resources = pikepdf.Dictionary(Font=pikepdf.Dictionary(F1=font))
        parent = pdf.make_stream(b"q /Inner Do Q")
        parent.Type = pikepdf.Name.XObject
        parent.Subtype = pikepdf.Name.Form
        parent.BBox = [0, 0, 400, 400]
        parent.Resources = pikepdf.Dictionary(XObject=pikepdf.Dictionary(Inner=child))
        picture = pdf.make_stream(bytes([10, 80, 140]) * 100)
        picture.Type = pikepdf.Name.XObject
        picture.Subtype = pikepdf.Name.Image
        picture.Width = 10
        picture.Height = 10
        picture.ColorSpace = pikepdf.Name.DeviceRGB
        picture.BitsPerComponent = 8
        page.Resources = pikepdf.Dictionary(
            XObject=pikepdf.Dictionary(Outer=parent, Picture=picture)
        )
        page.Contents = pdf.make_stream(
            b"q /Outer Do Q q 50 0 0 50 20 50 cm /Picture Do Q"
        )
        pdf.save(source)
    original_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    subprocess.run(
        [sys.executable, str(helper), str(source), str(output)],
        check=True,
        capture_output=True,
    )
    text = subprocess.check_output(["pdftotext", str(output), "-"], text=True)
    assert "VISIBLE_HEADER" in text and "VISIBLE_TAIL" in text
    assert "HIDDEN_MARKER" not in text and "MIXED_HIDDEN" in text
    for name, pdf_file in [("before", source), ("after", output)]:
        subprocess.run(
            ["pdftoppm", "-r", "72", "-singlefile", str(pdf_file), str(folder / name)],
            check=True,
            capture_output=True,
        )
    assert (folder / "before.ppm").read_bytes() == (folder / "after.ppm").read_bytes()
    assert hashlib.sha256(source.read_bytes()).hexdigest() == original_hash
    refusal = subprocess.run(
        [sys.executable, str(helper), str(source), str(output)],
        capture_output=True,
        check=False,
    )
    assert refusal.returncode != 0
print(
    "Nested hidden text removed; visible/mixed text, vectors, images and original bytes preserved; overwrite refused"
)
