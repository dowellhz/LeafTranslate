import glob
import json
import os
import tempfile


TEXT_TYPES = {"paragraph", "heading", "caption", "list item"}
PROTECTED_TYPES = {"table", "image", "figure", "picture", "formula", "chart"}


def extract_page_blocks(input_path, start_index, end_index):
    opendataloader_pdf = import_opendataloader()
    with tempfile.TemporaryDirectory(prefix="leaftranslate-opendataloader-") as output_dir:
        opendataloader_pdf.convert(
            input_path=input_path,
            output_dir=output_dir,
            format="json",
            quiet=True,
            pages=f"{start_index + 1}-{end_index}",
            table_method="cluster",
            reading_order="xycut",
            image_output="off",
        )
        document = load_converted_json(output_dir)
    return blocks_from_document(document, start_index, end_index)


def import_opendataloader():
    try:
        import opendataloader_pdf  # type: ignore
    except Exception as exc:
        raise RuntimeError(
            "OpenDataLoader backend is unavailable. Install Python 3.10+, Java 11+, and opendataloader-pdf."
        ) from exc
    return opendataloader_pdf


def load_converted_json(output_dir):
    candidates = sorted(glob.glob(os.path.join(output_dir, "**", "*.json"), recursive=True))
    if not candidates:
        raise RuntimeError("OpenDataLoader did not produce a JSON output file.")
    with open(candidates[0], "r", encoding="utf-8") as file:
        return json.load(file)


def blocks_from_document(document, start_index, end_index):
    page_map = {page_index: [] for page_index in range(start_index, end_index)}
    for element in document.get("kids", []):
        collect_element(element, page_map)
    return [(page_index, sorted(page_map[page_index], key=lambda item: (item["rect"].y0, item["rect"].x0))) for page_index in range(start_index, end_index)]


def collect_element(element, page_map, inherited_protected=False):
    element_type = str(element.get("type", "")).lower()
    protected = inherited_protected or element_type in PROTECTED_TYPES

    page_index = page_index_for_element(element)
    if page_index in page_map:
        block = block_from_element(element, protected)
        if block is not None:
            page_map[page_index].append(block)

    for child in child_elements(element):
        collect_element(child, page_map, protected)


def child_elements(element):
    children = []
    for key in ("kids", "list items"):
        value = element.get(key)
        if isinstance(value, list):
            children.extend(item for item in value if isinstance(item, dict))

    rows = element.get("rows")
    if isinstance(rows, list):
        for row in rows:
            if not isinstance(row, dict):
                continue
            cells = row.get("cells", [])
            if isinstance(cells, list):
                children.extend(cell for cell in cells if isinstance(cell, dict))

    return children


def block_from_element(element, protected):
    element_type = str(element.get("type", "")).lower()
    text = text_for_element(element)
    rect = rect_for_element(element)
    if rect is None:
        return None
    if not text and element_type not in PROTECTED_TYPES:
        return None

    font_size = float(element.get("font size") or 10)
    is_heading = element_type == "heading"
    return {
        "text": text,
        "rect": rect,
        "erase_rects": [rect],
        "font_size": max(6, font_size),
        "bold": is_heading,
        "title": is_heading and int(element.get("heading level") or 2) <= 1,
        "protected": protected or element_type in PROTECTED_TYPES,
    }


def text_for_element(element):
    content = element.get("content")
    if isinstance(content, str):
        return normalize_text(content)
    return ""


def normalize_text(text):
    return " ".join(text.split()).strip()


def page_index_for_element(element):
    page_number = element.get("page number")
    if isinstance(page_number, int) and page_number > 0:
        return page_number - 1
    return None


def rect_for_element(element):
    bbox = element.get("bounding box")
    if bbox is None:
        return None

    values = bbox_values(bbox)
    if values is None:
        return None
    x0, y0, x1, y1 = values
    if x1 <= x0 or y1 <= y0:
        return None

    try:
        import fitz

        return fitz.Rect(float(x0), float(y0), float(x1), float(y1))
    except Exception:
        return [float(x0), float(y0), float(x1), float(y1)]


def bbox_values(bbox):
    if isinstance(bbox, list) and len(bbox) >= 4:
        x0, y0, third, fourth = [float(value) for value in bbox[:4]]
        return normalize_bbox_values(x0, y0, third, fourth)

    if not isinstance(bbox, dict):
        return None

    lower = {str(key).lower(): value for key, value in bbox.items()}
    if all(key in lower for key in ("x0", "y0", "x1", "y1")):
        return (
            float(lower["x0"]),
            float(lower["y0"]),
            float(lower["x1"]),
            float(lower["y1"]),
        )
    if all(key in lower for key in ("left", "top", "right", "bottom")):
        return (
            float(lower["left"]),
            float(lower["top"]),
            float(lower["right"]),
            float(lower["bottom"]),
        )
    if all(key in lower for key in ("x", "y", "width", "height")):
        x0 = float(lower["x"])
        y0 = float(lower["y"])
        return x0, y0, x0 + float(lower["width"]), y0 + float(lower["height"])
    return None


def normalize_bbox_values(x0, y0, third, fourth):
    if third > x0 and fourth > y0:
        return x0, y0, third, fourth
    return x0, y0, x0 + third, y0 + fourth
