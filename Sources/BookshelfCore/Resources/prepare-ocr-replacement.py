"""Clear invisible text in page/Form streams in an OCR candidate copy.

OCRmyPDF redo strips page-level text but may retain old OCR inside Form XObjects.
Only text blocks whose text is entirely render-mode 3 are cleared. Visible text,
paint operators, positioning and graphics state remain. Unsupported mixed blocks remain.
"""

import argparse
import hashlib
from pathlib import Path

import pikepdf


def clear_hidden_blocks(instructions):
    mode, stack, result, block = 0, [], [], None
    hidden, shows, marked, removed = True, 0, 0, 0
    for item in instructions:
        op, args = str(item.operator), item.operands
        if op == "q":
            stack.append(mode)
        elif op == "Q":
            mode = stack.pop() if stack else 0
        elif op == "Tr":
            mode = int(args[0])
        if op == "BT":
            if block is not None:
                result.extend(block)
            block, hidden, shows, marked = [], True, 0, 0
        if block is None:
            result.append(item)
            continue
        block.append(item)
        if op in {"Tj", "TJ", "'", '"'}:
            shows += 1
            hidden = hidden and mode == 3 and op in {"Tj", "TJ"}
        if op in {"BDC", "BMC"}:
            marked += 1
            if op == "BDC" and not isinstance(args[1], pikepdf.Dictionary):
                hidden = False
        elif op == "EMC":
            marked -= 1
            if marked < 0:
                hidden = False
        if op == "ET":
            if hidden and shows and marked == 0:
                cleaned = []
                for token in block:
                    operator, operands = str(token.operator), token.operands
                    if operator in {"Tj", "TJ"}:
                        value = (
                            pikepdf.String(b"")
                            if operator == "Tj"
                            else pikepdf.Array([])
                        )
                        token = pikepdf.ContentStreamInstruction(
                            [value], token.operator
                        )
                    elif operator == "BDC" and "/ActualText" in operands[1]:
                        properties = pikepdf.Dictionary(operands[1])
                        del properties["/ActualText"]
                        token = pikepdf.ContentStreamInstruction(
                            [operands[0], properties], token.operator
                        )
                    cleaned.append(token)
                block = cleaned
                removed += shows
            result.extend(block)
            block = None
    if block is not None:
        result.extend(block)
    return result, removed


def strip_forms(pdf, container, seen):
    key = (
        container.objgen
        if isinstance(container, pikepdf.Stream)
        else container.obj.objgen
    )
    if key in seen:
        return 0
    seen.add(key)
    resources = container.get("/Resources", {})
    objects = resources.get("/XObject", {})
    removed, instructions = 0, []
    for item in pikepdf.parse_content_stream(container):
        if str(item.operator) == "Do":
            obj = objects.get(str(item.operands[0]))
            if isinstance(obj, pikepdf.Stream) and obj.get("/Subtype") == "/Form":
                removed += strip_forms(pdf, obj, seen)
        instructions.append(item)
    instructions, cleared = clear_hidden_blocks(instructions)
    removed += cleared
    if removed:
        data = pikepdf.unparse_content_stream(instructions)
        if isinstance(container, pikepdf.Stream):
            container.write(data)
        else:
            container.Contents = pdf.make_stream(data)
    return removed


def images(pdf):
    return sorted(
        hashlib.sha256(obj.read_raw_bytes()).hexdigest()
        for obj in pdf.objects
        if isinstance(obj, pikepdf.Stream) and obj.get("/Subtype") == "/Image"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.output.exists() or args.source.resolve() == args.output.resolve():
        raise SystemExit("Refusing to overwrite an existing PDF")
    with pikepdf.open(args.source) as pdf:
        if pdf.is_encrypted:
            raise SystemExit("Encrypted PDFs cannot be prepared")
        before = images(pdf)
        removed, seen = 0, set()
        for page in pdf.pages:
            removed += strip_forms(pdf, page, seen)
        if images(pdf) != before:
            raise SystemExit("Image data changed during preparation")
        pdf.save(args.output)
    with pikepdf.open(args.output) as result:
        if images(result) != before:
            raise SystemExit("Image data changed while saving preparation")
    print(f"Cleared {removed} invisible OCR text operands")


if __name__ == "__main__":
    main()
