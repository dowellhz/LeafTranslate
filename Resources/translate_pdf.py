#!/usr/bin/env python3
import json
import math
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed


ROOT = os.path.dirname(os.path.abspath(__file__))
PYTHON_DIR = os.path.join(ROOT, "python")
if os.path.isdir(PYTHON_DIR):
    sys.path.insert(0, PYTHON_DIR)

from llm_translation import request_translation_json, request_translation_text  # noqa: E402
from pdf_heuristics import CJK_BOLD_FONT_FILE, CJK_FONT_FILE, Heuristics  # noqa: E402

try:
    import fitz
except Exception as exc:
    print(f"PyMuPDF is not available: {exc}", file=sys.stderr)
    sys.exit(1)


def normalize_text(text):
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", text)
    return re.sub(r"\s+", " ", text).strip()


def normalize_translation_text(text):
    text = normalize_text(text)
    text = normalize_mixed_spacing(text)
    text = re.sub(
        r"(?<![A-Za-z0-9])(?:[A-Za-z0-9]\s+){2,}[A-Za-z0-9](?![A-Za-z0-9])",
        lambda match: re.sub(r"\s+", "", match.group(0)),
        text,
    )
    text = re.sub(r"([A-Za-z])\s+(\d)", r"\1\2", text)
    text = re.sub(r"(\d)\s+([A-Za-z])", r"\1\2", text)
    text = re.sub(r"([A-Za-z0-9])\s*-\s*([A-Za-z0-9])", r"\1-\2", text)
    text = re.sub(r"\b([A-Za-z])\?{1,3}\b", r"\1", text)
    text = re.sub(r"\?{1,3}(?=\s*[=,;)\]])", "", text)
    text = normalize_mixed_spacing(text)
    return text


def normalize_mixed_spacing(text):
    text = re.sub(r"\s+([，。；：！？、）】])", r"\1", text)
    text = re.sub(r"([（【])\s+", r"\1", text)
    text = re.sub(r"([\u3400-\u9fff])\s+([\u3400-\u9fff])", r"\1\2", text)
    ascii_term = r"A-Za-z0-9_.+/&-"
    text = re.sub(rf"([\u3400-\u9fff])([{ascii_term}]*[A-Za-z0-9])", r"\1 \2", text)
    text = re.sub(rf"([{ascii_term}]*[A-Za-z0-9])([\u3400-\u9fff])", r"\1 \2", text)
    text = re.sub(r"\s{2,}", " ", text)
    return text.strip()


def looks_like_garbled_translation(text, settings=None):
    text = normalize_text(text)
    if not text:
        return False

    question_count = text.count("?")
    non_space_count = len([char for char in text if not char.isspace()])
    if question_count >= Heuristics.GARBLED_QUESTION_MIN_COUNT and question_count / max(non_space_count, 1) >= Heuristics.GARBLED_QUESTION_RATIO:
        return True

    if re.search(r"\?{4,}", text):
        return True

    if settings and target_is_cjk(settings) and question_count >= 3 and not contains_cjk(text):
        return True

    return False


MATH_PLACEHOLDER_RE = re.compile(r"MATHPH_[0-9]+")
MATH_FRAGMENT_RE = re.compile(
    r"("
    r"[\U0001D400-\U0001D7FFℒ∑Σ√∫∞≈≠≤≥]\S*(?:\s*[+\-−=:/()[\],;·]\s*\S+){0,4}"
    r"|[A-Za-z][A-Za-z0-9_]*\s*[×x]\s*[A-Za-z0-9_]+"
    r"|\d+\s*[×x]\s*(?:\d+|[A-Za-z][A-Za-z0-9_]*)"
    r"|[A-Za-z]\s*[=<>≤≥]\s*[^，。；:：,;]{1,28}"
    r")"
)
MATH_LETTER_MAP = str.maketrans(
    {
        "𝐴": "A",
        "𝐵": "B",
        "𝐶": "C",
        "𝐷": "D",
        "𝐸": "E",
        "𝐹": "F",
        "𝐺": "G",
        "𝐻": "H",
        "𝐼": "I",
        "𝐽": "J",
        "𝐾": "K",
        "𝐿": "L",
        "𝑀": "M",
        "𝑁": "N",
        "𝑂": "O",
        "𝑃": "P",
        "𝑄": "Q",
        "𝑅": "R",
        "𝑆": "S",
        "𝑇": "T",
        "𝑈": "U",
        "𝑉": "V",
        "𝑊": "W",
        "𝑋": "X",
        "𝑌": "Y",
        "𝑍": "Z",
        "𝑎": "a",
        "𝑏": "b",
        "𝑐": "c",
        "𝑑": "d",
        "𝑒": "e",
        "𝑓": "f",
        "𝑔": "g",
        "ℎ": "h",
        "𝑖": "i",
        "𝑗": "j",
        "𝑘": "k",
        "𝑙": "l",
        "𝑚": "m",
        "𝑛": "n",
        "𝑜": "o",
        "𝑝": "p",
        "𝑞": "q",
        "𝑟": "r",
        "𝑠": "s",
        "𝑡": "t",
        "𝑢": "u",
        "𝑣": "v",
        "𝑤": "w",
        "𝑥": "x",
        "𝑦": "y",
        "𝑧": "z",
        "ℒ": "L",
        "𝜆": "lambda",
    }
)


def protect_math_fragments(text):
    replacements = []

    def replace(match):
        value = match.group(0).strip()
        if not should_mask_math_fragment(value):
            return match.group(0)
        placeholder = f"MATHPH_{len(replacements) + 1}"
        replacements.append((placeholder, value))
        leading = match.group(0)[: len(match.group(0)) - len(match.group(0).lstrip())]
        trailing = match.group(0)[len(match.group(0).rstrip()) :]
        return f"{leading}{placeholder}{trailing}"

    return MATH_FRAGMENT_RE.sub(replace, text), replacements


def should_mask_math_fragment(value):
    if not value:
        return False
    if len(value) > Heuristics.MATH_FRAGMENT_MAX_LENGTH:
        return False
    if re.fullmatch(r"[A-Za-z]{4,}", value):
        return False
    return bool(
        re.search(r"[\U0001D400-\U0001D7FFℒ∑Σ√∫∞≈≠≤≥]", value)
        or re.search(r"[A-Za-z0-9_]\s*[×x]\s*[A-Za-z0-9_]", value)
        or re.search(r"[A-Za-z]\s*[=<>≤≥]", value)
    )


def restore_math_fragments(text, replacements):
    for placeholder, value in replacements:
        text = text.replace(placeholder, display_math_fragment(value))
    return normalize_restored_math_spacing(text)


def normalize_restored_math_spacing(text):
    text = re.sub(r"\b([A-Z][a-z]?)\s*×\s*([A-Z][a-z]?)(elements|tokens|channels)\b", r"\1 × \2 \3", text)
    text = re.sub(r"\b([A-Z][a-z]?)(elements|tokens|channels)\b", r"\1 \2", text)
    text = re.sub(r"\b(\d+)(PP|TP|EP|DP|MTP)\s+(times|elements|tokens|channels)\b", r"\1 \2 \3", text)
    text = re.sub(r"\b(PP|TP|EP|DP|MTP)(times|elements|tokens|channels)\b", r"\1 \2", text)
    text = re.sub(r"\s{2,}", " ", text)
    return text.strip()


def display_math_fragment(value):
    value = normalize_text(value)
    value = value.translate(MATH_LETTER_MAP)
    value = re.sub(r"\s+", " ", value).strip()
    value = re.sub(r"\b([A-Za-z]{1,3})\s+([A-Za-z]{1,3})(?=\[)", r"\1_\2", value)
    value = re.sub(r"\b([A-Za-z]{1,3})\s+([A-Za-z]{1,3})\b(?!\s*[A-Za-z])", r"\1_\2", value)
    value = re.sub(r"([A-Za-z])\s+(\d)", r"\1\2", value)
    value = re.sub(r"(\d)\s+([A-Za-z])", r"\1\2", value)
    value = value.replace("−", "-")
    value = value.replace("×", " × ")
    value = re.sub(r"\s+", " ", value).strip()
    value = re.sub(r"\b([A-Z][a-z]?)\s*×\s*([A-Z][a-z]?)\b", r"\1 × \2", value)
    terms = "|".join(Heuristics.TECHNICAL_TERMS_FOR_SPACING)
    value = re.sub(rf"\b({terms})(times|elements|tokens|channels)\b", r"\1 \2", value)
    value = re.sub(r"\b([A-Z][a-z]?)×([A-Z][a-z]?)(elements|tokens|channels)\b", r"\1 × \2 \3", value)
    return value


def contains_cjk(text):
    return any("\u3400" <= char <= "\u9fff" for char in text)


def target_is_cjk(settings):
    target_language = (settings.get("targetLanguage") or "").lower()
    return any(name in target_language for name in Heuristics.CJK_TARGET_NAMES)


def english_word_count(text):
    return len(re.findall(r"[A-Za-z]{3,}", text))


def looks_like_toc_entry(text):
    text = normalize_text(text)
    if not text:
        return False
    if Heuristics.TOC_DOT_LEADER_PATTERN.search(text):
        return True
    return bool(Heuristics.TOC_NUMBERED_ENTRY_PATTERN.match(text))


def looks_like_name_or_affiliation_block(text):
    text = normalize_text(text)
    if not text:
        return False
    if looks_like_toc_entry(text):
        return False

    lowered = text.lower()
    if any(term in lowered for term in Heuristics.AFFILIATION_TERMS):
        return True

    words = re.findall(r"[A-Za-z]{2,}", text)
    if len(words) < 4:
        return False

    capitalized = sum(1 for word in words if word[:1].isupper())
    has_author_markers = bool(re.search(r"\b[A-Z][a-z]+[0-9,]*\b", text)) and bool(re.search(r"\d|,", text))
    prose_hits = sum(1 for word in words if word.lower() in Heuristics.AUTHOR_PROSE_TERMS)
    return has_author_markers and capitalized / max(len(words), 1) >= 0.65 and prose_hits <= 1


def cjk_ratio(text):
    meaningful = [char for char in text if not char.isspace()]
    if not meaningful:
        return 0
    cjk_count = sum(1 for char in meaningful if "\u3400" <= char <= "\u9fff")
    return cjk_count / len(meaningful)


def font_options_for_text(text, bold=False):
    if contains_cjk(text) and cjk_ratio(text) >= 0.18:
        font_file = CJK_BOLD_FONT_FILE if bold else CJK_FONT_FILE
        if font_file:
            return {"fontname": "cjk-bold" if bold else "cjk-mixed", "fontfile": font_file}
        return {"fontname": "china-s"}
    return {"fontname": "hebo" if bold else "helv"}


def translated_font_size(block, text=None):
    source_size = block["font_size"]
    text = text or block.get("translation", "") or block.get("text", "")
    if block.get("title"):
        return max(17, min(22, source_size * 0.98))
    if contains_cjk(text):
        if source_size >= 18:
            return min(19, source_size * 0.90)
        if source_size >= 14:
            return min(13.5, source_size * 0.80)
        if source_size >= 11.5:
            return min(10.6, source_size * 0.80)
        return max(6.2, min(9.8, source_size * 0.82))
    if source_size >= 18:
        return min(18, source_size * 0.86)
    if source_size >= 14:
        return min(15, source_size * 0.86)
    if source_size >= 11.5:
        return min(12, source_size * 0.86)
    return max(6.5, min(10.5, source_size * 0.88))


def should_protect_block(block):
    if looks_like_toc_entry(block["text"]) and not block.get("translate_toc", Heuristics.TRANSLATE_TOC_DEFAULT):
        return True
    if block.get("protected"):
        return True
    if looks_like_document_marker(block):
        return True
    if looks_like_name_or_affiliation_block(block["text"]):
        return True
    return looks_like_formula_or_math(block["text"]) or looks_like_chart_or_icon_text(block)


def looks_like_document_marker(block):
    text = normalize_text(block.get("text", ""))
    rect = block.get("rect")
    if not text or rect is None:
        return False
    if text.lower().startswith(Heuristics.DOCUMENT_MARKER_PREFIXES):
        return True
    if "arxiv:" in text.lower() and rect.height > rect.width * 3:
        return True
    if rect.width <= 40 and rect.height >= 120 and Heuristics.DOCUMENT_MARKER_PATTERN.search(text):
        return True
    return False


def looks_like_formula_or_math(text):
    text = normalize_text(text)
    if looks_like_toc_entry(text):
        return False
    compact = re.sub(r"\s+", "", text)
    if not compact:
        return True

    words = re.findall(r"[A-Za-z]{3,}", text)
    unicode_math_count = sum(1 for char in compact if "\U0001D400" <= char <= "\U0001D7FF")
    formula_word_count = sum(1 for word in words if word in Heuristics.FORMULA_WORDS)

    if len(words) >= 8 and unicode_math_count < 4 and formula_word_count == 0:
        return False

    math_count = sum(1 for char in compact if char in Heuristics.MATH_CHARS)
    digit_count = sum(1 for char in compact if char.isdigit())
    symbol_count = sum(1 for char in compact if not char.isalnum())
    math_density = (digit_count + symbol_count) / max(len(compact), 1)

    if unicode_math_count >= 3 and len(compact) <= 220:
        return True

    if formula_word_count > 0 and (math_count >= 1 or unicode_math_count >= 1) and len(compact) <= 220:
        return True

    if math_count >= 2 and math_density >= 0.28:
        return True

    if len(compact) <= 80 and re.search(r"([A-Za-z]\^|_[A-Za-z0-9]|\b[a-zA-Z]\s*=\s*)", text):
        return True

    if symbol_count >= 3 and digit_count >= 1 and len(compact) <= 28:
        return True

    return False


def looks_like_chart_or_icon_text(block):
    text = block["text"].strip()
    if not text:
        return True
    if looks_like_toc_entry(text):
        return False

    tokens = re.findall(r"[A-Za-z]+|\d+(?:\.\d+)?|[^\sA-Za-z\d]", text)
    if not tokens:
        return True

    digit_tokens = sum(1 for token in tokens if re.fullmatch(r"\d+(?:\.\d+)?", token))
    short_tokens = sum(1 for token in tokens if len(token) <= 2)
    digit_chars = sum(1 for char in text if char.isdigit())
    non_space_chars = sum(1 for char in text if not char.isspace())
    digit_ratio_value = digit_chars / max(non_space_chars, 1)
    short_token_ratio = short_tokens / max(len(tokens), 1)
    long_words = sum(1 for token in tokens if re.fullmatch(r"[A-Za-z]{4,}", token))

    if long_words >= 8:
        return False

    if digit_tokens >= 5 and (digit_ratio_value >= 0.22 or short_token_ratio >= 0.68):
        return True

    if len(tokens) >= 12 and short_token_ratio >= 0.82:
        return True

    if non_space_chars <= 2 and block["rect"].height <= 16:
        return True

    return False


def visual_regions(page):
    regions = []
    for drawing in page.get_drawings():
        rect = drawing.get("rect")
        if rect and not rect.is_empty and rect.width >= 8 and rect.height >= 8:
            regions.append(fitz.Rect(rect))

    for block in page.get_text("dict", sort=True).get("blocks", []):
        if block.get("type") == 1:
            bbox = block.get("bbox", [0, 0, 0, 0])
            regions.append(fitz.Rect(float(bbox[0]), float(bbox[1]), float(bbox[2]), float(bbox[3])))
    return regions


def is_visual_label(text, rect, font_size, regions):
    if not center_inside_visual_region(rect, regions):
        return False

    token_count = len(re.findall(r"[A-Za-z]+|\d+(?:\.\d+)?|[^\sA-Za-z\d]", text))
    compact_length = len(re.sub(r"\s+", "", text))
    if font_size <= 9.5 or rect.height <= 16:
        return True
    if compact_length <= 24 and token_count <= 5:
        return True
    return looks_like_chart_or_icon_text({"text": text, "rect": rect})


def center_inside_visual_region(rect, regions):
    center = fitz.Point((rect.x0 + rect.x1) / 2, (rect.y0 + rect.y1) / 2)
    for region in regions:
        if center in region:
            return True
    return False


def text_blocks(page):
    blocks = page.get_text("dict", sort=True).get("blocks", [])
    protected_regions = visual_regions(page)
    result = []
    for block in blocks:
        if block.get("type") != 0:
            continue

        lines = []
        font_sizes = []
        bold_chars = 0
        total_chars = 0
        erase_rects = []
        for line in block.get("lines", []):
            spans = line.get("spans", [])
            text = normalize_text("".join(span.get("text", "") for span in spans))
            if not text:
                continue
            bbox = line.get("bbox", [0, 0, 0, 0])
            lines.append(text)
            erase_rects.append(fitz.Rect(float(bbox[0]), float(bbox[1]), float(bbox[2]), float(bbox[3])))
            for span in spans:
                font_sizes.append(float(span.get("size", 12)))
                span_text = normalize_text(span.get("text", ""))
                span_length = len(span_text.strip())
                total_chars += span_length
                if span_is_bold(span):
                    bold_chars += span_length

        text = normalize_text(" ".join(lines))
        if not text:
            continue

        bbox = block.get("bbox", [0, 0, 0, 0])
        rect = fitz.Rect(float(bbox[0]), float(bbox[1]), float(bbox[2]), float(bbox[3]))
        font_size = max(6, sum(font_sizes) / len(font_sizes)) if font_sizes else 10
        title = looks_like_title_block(text, rect, font_size, page.rect)
        bold = total_chars > 0 and bold_chars / total_chars >= 0.35
        result.append(
            {
                "text": text,
                "rect": rect,
                "erase_rects": erase_rects,
                "font_size": font_size,
                "bold": bold or title or looks_like_bold_heading(text, rect, font_size, page.rect),
                "title": title,
                "protected": is_visual_label(text, rect, font_size, protected_regions),
            }
        )
    return merge_drop_caps(result)


def span_is_bold(span):
    font = str(span.get("font", "")).lower()
    flags = int(span.get("flags", 0))
    return bool(flags & 16) or any(name in font for name in ["bold", "black", "heavy", "semibold", "demi"])


def looks_like_bold_heading(text, rect, font_size, page_rect):
    text = text.strip()
    if not text or len(text) > 140:
        return False
    if re.match(r"^\d+(?:\.\d+)*\.?\s+\S+", text):
        return True
    if font_size < 12:
        return False
    if rect.width > page_rect.width * 0.82 and len(text) > 90:
        return False
    words = re.findall(r"[A-Za-z]{2,}", text)
    if 1 <= len(words) <= 12 and not text.endswith((".", ",", ";", ":")):
        return True
    return False


def looks_like_title_block(text, rect, font_size, page_rect):
    if font_size < 17:
        return False
    if rect.y0 > page_rect.height * 0.22:
        return False
    if rect.width < page_rect.width * 0.45:
        return False
    if len(text) < 12 or len(text) > 180:
        return False
    return True


def merge_drop_caps(blocks):
    merged = []
    consumed = set()

    for index, block in enumerate(blocks):
        if index in consumed:
            continue

        body_indexes = drop_cap_body_indexes(block, blocks, index, consumed)
        if not body_indexes:
            merged.append(block)
            continue

        consumed.add(index)
        for body_index in body_indexes:
            consumed.add(body_index)

        group = [block] + [blocks[body_index] for body_index in body_indexes]
        merged.append(merge_block_group(group))

    return sorted(merged, key=lambda item: (item["rect"].y0, item["rect"].x0))


def drop_cap_body_indexes(candidate, blocks, candidate_index, consumed):
    text = candidate["text"].strip()
    if len(text) > 2 or not re.match(r"^[A-Za-z]$", text):
        return []

    rect = candidate["rect"]
    if rect.height < max(24, candidate["font_size"] * 1.8):
        return []

    nearby = []
    for index, block in enumerate(blocks):
        if index == candidate_index or index in consumed:
            continue

        other = block["rect"]
        if other.x0 < rect.x0 - 4:
            continue
        if other.x0 > rect.x1 + rect.width * 3.5:
            continue
        if other.y0 > rect.y1 + rect.height * 0.8:
            continue
        if other.y1 < rect.y0 - rect.height * 0.2:
            continue
        if block["font_size"] >= candidate["font_size"] * 0.85:
            continue
        if not block["text"].strip():
            continue

        vertical_overlap = min(rect.y1, other.y1) - max(rect.y0, other.y0)
        close_below = 0 <= other.y0 - rect.y1 <= rect.height * 0.35
        if vertical_overlap > 0 or close_below:
            nearby.append(index)

    nearby.sort(key=lambda item: (blocks[item]["rect"].y0, blocks[item]["rect"].x0))
    return nearby[:2]


def merge_block_group(group):
    sorted_group = sorted(group, key=lambda item: (item["rect"].y0, item["rect"].x0))
    rect = fitz.Rect(sorted_group[0]["rect"])
    texts = []
    font_sizes = []
    bold_count = 0
    protected = False
    for block in sorted_group:
        rect |= block["rect"]
        texts.append(block["text"])
        font_sizes.append(block["font_size"])
        if block.get("bold", False):
            bold_count += 1
        protected = protected or block.get("protected", False)

    return {
        "text": normalize_text(" ".join(texts)),
        "rect": rect,
        "erase_rects": [erase_rect for block in sorted_group for erase_rect in block["erase_rects"]],
        "font_size": sum(font_sizes) / len(font_sizes),
        "bold": bold_count >= max(1, len(sorted_group) // 2),
        "title": any(block.get("title", False) for block in sorted_group),
        "protected": protected,
    }


def translate_text(text, settings):
    target_language = settings.get("targetLanguage") or "Chinese"
    masked_text, math_replacements = protect_math_fragments(text)

    instructions = (
        f"Translate the user's prose, headings, captions, and table/figure descriptions into {target_language}. "
        "Keep formulas, variable names, model names, citations, URLs, and table/chart cell values unchanged inside the translation. "
        "If the text is a caption or normal paragraph, it must be translated even if it mentions figures, tables, or formulas. "
        "Preserve every MATHPH_N placeholder exactly. "
        "Return only the translation."
    )

    translated = request_translation_text(settings, instructions, masked_text, max_tokens=2048)
    return restore_math_fragments(translated, math_replacements)


def translate_page_blocks(blocks, settings, page_number):
    translatable = []
    math_replacements_by_id = {}
    for index, block in enumerate(blocks, start=1):
        block["id"] = index
        block["translate_toc"] = bool(settings.get("translateTOC", Heuristics.TRANSLATE_TOC_DEFAULT))
        block["protected"] = should_protect_block(block)
        if block["protected"]:
            continue
        masked_text, math_replacements = protect_math_fragments(block["text"])
        math_replacements_by_id[index] = math_replacements
        translatable.append({"id": index, "text": masked_text})

    if not translatable:
        return {}

    try:
        translations = translate_blocks_as_page(translatable, settings, page_number)
        translations = restore_page_math_fragments(translations, math_replacements_by_id)
        retry_ids = invalid_translation_ids(translatable, translations, settings)
        if retry_ids:
            emit_warning(page_number, f"Retrying untranslated or garbled block ids: {retry_ids}")
            translations.update(
                retry_translation_items(
                    [item for item in translatable if item["id"] in retry_ids],
                    settings,
                    page_number,
                    math_replacements_by_id,
                )
            )
        validate_translations(translatable, translations, settings)
        return translations
    except Exception as exc:
        print(
            json.dumps(
                {"page": page_number, "status": "fallback", "reason": str(exc)},
                ensure_ascii=False,
            ),
            flush=True,
        )
        translations = retry_translation_items(translatable, settings, page_number, math_replacements_by_id)
        try:
            validate_translations(translatable, translations, settings)
        except Exception as validation_error:
            emit_warning(page_number, str(validation_error))
        return translations


def retry_translation_items(items, settings, page_number, math_replacements_by_id):
    max_workers = int(settings.get("fallbackConcurrency", Heuristics.FALLBACK_CONCURRENCY))
    max_workers = max(1, min(max_workers, len(items)))
    translations = {}

    def translate_item(item):
        translated = normalize_translation_text(translate_text(item["text"], settings))
        translated = restore_math_fragments(translated, math_replacements_by_id.get(item["id"], []))
        if not translated.strip():
            emit_warning(page_number, f"Block {item['id']} fallback returned empty text; original text kept.")
            return item["id"], item["text"]
        if looks_like_garbled_translation(translated, settings):
            emit_warning(page_number, f"Block {item['id']} fallback returned garbled text; original text kept.")
            return item["id"], item["text"]
        return item["id"], translated

    if max_workers == 1:
        for item in items:
            item_id, translated = translate_item(item)
            translations[item_id] = translated
        return translations

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(translate_item, item) for item in items]
        for future in as_completed(futures):
            item_id, translated = future.result()
            translations[item_id] = translated
    return translations


def restore_page_math_fragments(translations, replacements_by_id):
    return {
        item_id: normalize_translation_text(restore_math_fragments(text, replacements_by_id.get(item_id, [])))
        for item_id, text in translations.items()
    }


def emit_warning(page_number, message):
    print(
        json.dumps(
            {"page": page_number, "status": "warning", "message": message},
            ensure_ascii=False,
        ),
        flush=True,
    )


def validate_translations(items, translations, settings):
    untranslated = invalid_translation_ids(items, translations, settings)
    if untranslated:
        raise RuntimeError(f"LLM returned untranslated prose ids: {untranslated}")


def invalid_translation_ids(items, translations, settings):
    if not target_is_cjk(settings):
        return []

    untranslated = []
    for item in items:
        source = item["text"]
        translated = translations.get(item["id"], "")
        if english_word_count(source) < 8:
            continue
        if looks_like_name_or_affiliation_block(source):
            continue
        if not translated.strip():
            untranslated.append(item["id"])
            continue
        if looks_like_garbled_translation(translated, settings):
            untranslated.append(item["id"])
            continue
        if contains_cjk(translated):
            continue
        if english_word_count(translated) >= max(6, english_word_count(source) * 0.45):
            untranslated.append(item["id"])

    return untranslated


def has_translatable_prose(blocks):
    for block in blocks:
        if block.get("protected"):
            continue
        if english_word_count(block.get("text", "")) >= 8:
            return True
    return False


def validate_written_page(blocks, inserted_texts, settings, page_number):
    if not target_is_cjk(settings) or not has_translatable_prose(blocks):
        return True

    if any(contains_cjk(text) for text in inserted_texts):
        return True

    emit_warning(page_number, f"Page {page_number} has prose but no Chinese translation was written.")
    return False


def looks_untranslated_for_target(source, translated, settings):
    if not target_is_cjk(settings):
        return False
    if looks_like_garbled_translation(translated, settings):
        return True
    if english_word_count(source) < 8:
        return False
    if looks_like_name_or_affiliation_block(source):
        return False
    return not contains_cjk(translated)


def translate_blocks_as_page(items, settings, page_number):
    target_language = settings.get("targetLanguage") or "Chinese"
    source_json = json.dumps(items, ensure_ascii=False)
    prompt = (
        f"Translate the following PDF page text blocks into {target_language}.\n"
        "Use surrounding blocks as page context, but translate each block independently.\n"
        "Translate normal prose, headings, figure captions, table captions, and descriptive paragraphs. "
        "Do not return these prose blocks unchanged unless they are already in the target language.\n"
        "If a block is only chart text, image labels, mathematical formulas, mathematical symbols, code, "
        "URLs, citations, variable lists, or table values, return that block unchanged.\n"
        "A caption beginning with Figure, Table, Fig., or Tab. is prose and must be translated, while preserving the label and number.\n"
        "Inside translated prose, preserve variable letters, model names, citations, URLs, and formula fragments exactly, "
        "without translating or rewriting technical identifiers. "
        "Never replace variables, formulas, or unknown glyphs with placeholder boxes.\n"
        "Return strict JSON only, with this schema: "
        "[{\"id\": number, \"translation\": string}].\n"
        "Keep every id exactly once. Do not include markdown fences.\n\n"
        f"Page: {page_number}\nBlocks:\n{source_json}"
    )

    parsed = request_translation_json(
        settings,
        "You are a precise PDF translation engine. Return only valid JSON.",
        prompt,
        max_tokens=8192,
    )
    translations = {}
    expected_ids = {item["id"] for item in items}
    for item in parsed:
        item_id = int(item.get("id"))
        if item_id in expected_ids:
            translations[item_id] = normalize_translation_text(str(item.get("translation", "")))

    missing_ids = expected_ids - set(translations.keys())
    if missing_ids:
        raise RuntimeError(f"LLM response missing ids: {sorted(missing_ids)}")
    return translations

def text_width_units(text):
    units = 0.0
    for char in text:
        if char.isspace():
            units += 0.35
        elif "\u3400" <= char <= "\u9fff":
            units += 1.0
        elif char.isupper() or char.isdigit():
            units += 0.62
        elif char in ".,;:!?()[]{}'\"`-_/&+":
            units += 0.35
        else:
            units += 0.52
    return units


def estimated_line_count(text, rect, font_size):
    if not text:
        return 1
    average_char_width = font_size * (0.92 if contains_cjk(text) else 0.54)
    line_units = max(8.0, rect.width / max(average_char_width, 1))
    return max(1, int(text_width_units(text) / line_units) + 1)


def text_lineheight(text):
    return 1.44 if contains_cjk(text) else 1.34


def expanded_text_rect(block, page):
    rect = fitz.Rect(block["rect"])
    text = block.get("translation", "")
    font_size = translated_font_size(block, text)
    lineheight = text_lineheight(text)
    source_lines = max(1, len(block.get("erase_rects", [])))
    translated_lines = estimated_line_count(text, rect, font_size)
    required_height = translated_lines * font_size * lineheight + font_size * 0.9
    source_height = max(rect.height, source_lines * font_size * lineheight + font_size * 0.6)
    rect.y1 = max(rect.y1, rect.y0 + source_height, rect.y0 + required_height)
    rect.y1 = min(page.rect.y1 - 20, rect.y1)
    return rect


def valid_text_rect(rect):
    values = [rect.x0, rect.y0, rect.x1, rect.y1, rect.width, rect.height]
    return all(math.isfinite(value) for value in values) and rect.width >= 2 and rect.height >= 2


def erase_original_text(page, block):
    for erase_rect in block["erase_rects"]:
        safe_rect = fitz.Rect(erase_rect)
        if not valid_text_rect(safe_rect):
            continue
        safe_rect.x0 -= 1.0
        safe_rect.x1 += 1.0
        safe_rect.y0 -= 0.5
        safe_rect.y1 += 0.5
        page.draw_rect(safe_rect, color=None, fill=(1, 1, 1), overlay=True)


def translation_layout(page, block, text):
    block["translation"] = text
    rect = expanded_text_rect(block, page)
    if not valid_text_rect(rect):
        return None, None
    font_size = translated_font_size(block, text)
    lineheight = text_lineheight(text)
    bold = block.get("bold", False)

    for _ in range(Heuristics.LAYOUT_FIT_ATTEMPTS):
        if not valid_text_rect(rect):
            return None, None
        temp_doc = fitz.open()
        temp_page = temp_doc.new_page(width=page.rect.width, height=page.rect.height)
        try:
            remaining = temp_page.insert_textbox(
                rect,
                text,
                fontsize=font_size,
                lineheight=lineheight,
                color=(0.08, 0.10, 0.15),
                align=fitz.TEXT_ALIGN_LEFT,
                **font_options_for_text(text, bold=bold),
            )
        except ValueError:
            temp_doc.close()
            return None, None
        temp_doc.close()
        if remaining >= 0:
            return rect, font_size
        font_size *= Heuristics.LAYOUT_FONT_SHRINK
        lineheight = max(1.32, lineheight - 0.02)
        rect.y1 = min(page.rect.y1 - 20, rect.y1 + Heuristics.LAYOUT_BOX_GROWTH)
    return None, None


def insert_translation(page, rect, font_size, text):
    # The caller stores source styling on the block; this wrapper accepts both old and new call sites.
    insert_translation_with_style(page, rect, font_size, text, bold=False)


def insert_translation_with_style(page, rect, font_size, text, bold=False):
    if not valid_text_rect(rect) or not text.strip():
        return
    page.insert_textbox(
        rect,
        text,
        fontsize=font_size,
        lineheight=text_lineheight(text),
        color=(0.08, 0.10, 0.15),
        align=fitz.TEXT_ALIGN_LEFT,
        **font_options_for_text(text, bold=bold),
    )


def append_source_page(out_doc, source_doc, page_index):
    out_doc.insert_pdf(source_doc, from_page=page_index, to_page=page_index)


def append_translation_page(out_doc, source_doc, page_index):
    out_doc.insert_pdf(source_doc, from_page=page_index, to_page=page_index)
    return out_doc[-1]


def write_translation_page(out_doc, source_doc, page_index, blocks, settings):
    append_source_page(out_doc, source_doc, page_index)
    page = append_translation_page(out_doc, source_doc, page_index)
    translations = translate_page_blocks(blocks, settings, page_index + 1)
    inserted_texts = []
    for block in blocks:
        if block.get("protected"):
            continue

        translated = translations.get(block["id"], "")
        if not translated:
            continue
        if looks_untranslated_for_target(block.get("text", ""), translated, settings):
            emit_warning(page_index + 1, f"Block {block['id']} returned untranslated prose; original text kept.")
            continue

        rect, font_size = translation_layout(page, block, translated)
        if rect is not None:
            erase_original_text(page, block)
            insert_translation_with_style(page, rect, font_size, translated, bold=block.get("bold", False))
            inserted_texts.append(translated)
        elif target_is_cjk(settings) and english_word_count(block.get("text", "")) >= 8:
            emit_warning(page_index + 1, f"Block {block['id']} translation did not fit; original text kept.")
    validate_written_page(blocks, inserted_texts, settings, page_index + 1)
    return page


def translate_pdf(input_path, output_path, settings, start_page, page_limit):
    source_doc = fitz.open(input_path)
    out_doc = fitz.open()
    try:
        start_index, end_index = page_range(source_doc, start_page, page_limit)
        for page_index in range(start_index, end_index):
            translate_one_page(out_doc, source_doc, page_index, settings)
        out_doc.save(output_path, garbage=4, deflate=True)
    finally:
        out_doc.close()
        source_doc.close()


def translate_one_page(out_doc, source_doc, page_index, settings):
    source_page = source_doc[page_index]
    write_translation_page(out_doc, source_doc, page_index, text_blocks(source_page), settings)
    print(json.dumps({"page": page_index + 1, "status": "done"}, ensure_ascii=False), flush=True)


def page_range(doc, start_page, page_limit):
    start_index = max(0, start_page - 1)
    if start_index >= doc.page_count:
        raise RuntimeError(f"Start page {start_page} is outside the PDF.")
    return start_index, min(doc.page_count, start_index + page_limit)


def load_settings(path):
    with open(path, "r", encoding="utf-8") as file:
        return json.load(file)


def parse_args(argv):
    if len(argv) != 6:
        raise RuntimeError("Usage: translate_pdf.py input.pdf output.pdf settings.json start_page page_limit")
    return argv[1], argv[2], argv[3], int(argv[4]), int(argv[5])


def main():
    input_path, output_path, settings_path, start_page, page_limit = parse_args(sys.argv)
    translate_pdf(input_path, output_path, load_settings(settings_path), start_page, page_limit)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
