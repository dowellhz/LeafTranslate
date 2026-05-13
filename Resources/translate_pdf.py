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
    import opendataloader_adapter  # noqa: E402
except Exception:
    opendataloader_adapter = None

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


def cjk_char_count(text):
    return sum(1 for char in text if "\u3400" <= char <= "\u9fff")


def cjk_prose_char_count(text):
    return sum(1 for char in text if "\u4e00" <= char <= "\u9fff")


def contains_kana(text):
    return any("\u3040" <= char <= "\u30ff" for char in text)


def contains_hangul(text):
    return any("\uac00" <= char <= "\ud7af" for char in text)


def contains_cjk_compatible_text(text):
    return contains_cjk(text) or contains_kana(text) or contains_hangul(text)


def target_is_cjk(settings):
    target_language = normalized_target_language(settings).lower()
    return target_language in {"chinese", "japanese", "korean"}


def target_is_latin_language(settings):
    target_language = normalized_target_language(settings).lower()
    return target_language in {"english", "spanish", "french"}


def contains_target_language_script(text, settings):
    target_language = normalized_target_language(settings).lower()
    if target_language == "japanese":
        return contains_kana(text)
    if target_language == "korean":
        return contains_hangul(text)
    if target_language == "chinese":
        return contains_cjk(text) and not contains_kana(text) and not contains_hangul(text)
    if target_language in {"english", "spanish", "french"}:
        return bool(re.search(r"[A-Za-zÀ-ÖØ-öø-ÿ]{3,}", text))
    return True


def normalized_target_language(settings):
    target_language = normalize_text(settings.get("targetLanguage") or "Chinese")
    aliases = {
        "中文": "Chinese",
        "简体中文": "Chinese",
        "chinese": "Chinese",
        "zh": "Chinese",
        "cn": "Chinese",
        "英文": "English",
        "english": "English",
        "en": "English",
        "西班牙语": "Spanish",
        "spanish": "Spanish",
        "es": "Spanish",
        "法语": "French",
        "french": "French",
        "fr": "French",
        "日语": "Japanese",
        "japanese": "Japanese",
        "ja": "Japanese",
        "韩语": "Korean",
        "korean": "Korean",
        "ko": "Korean",
    }
    return aliases.get(target_language.lower(), aliases.get(target_language, target_language or "Chinese"))


def english_word_count(text):
    return len(re.findall(r"[A-Za-z]{3,}", text))


def normalized_for_language_compare(text):
    return re.sub(r"\s+", " ", normalize_text(text)).strip().lower()


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
    if contains_cjk_compatible_text(text) and (contains_kana(text) or contains_hangul(text) or cjk_ratio(text) >= 0.18):
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
    if contains_cjk_compatible_text(text):
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
    if cjk_prose_char_count(block["text"]) >= Heuristics.CJK_PROSE_PROTECT_BYPASS_CHARS:
        return False
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
    mark_table_like_blocks(result, page.rect)
    return merge_drop_caps(result)


def mark_table_like_blocks(blocks, page_rect):
    candidates = []
    for block in sorted(blocks, key=lambda item: (item["rect"].y0, item["rect"].x0)):
        if compact_table_line_candidate(block):
            candidates.append(block)

    group = []
    for block in candidates:
        if not group:
            group = [block]
            continue

        previous = group[-1]
        vertical_gap = block["rect"].y0 - previous["rect"].y1
        x0_drift = abs(block["rect"].x0 - previous["rect"].x0)
        x1_drift = abs(block["rect"].x1 - previous["rect"].x1)
        if vertical_gap <= 9 and x0_drift <= 48 and x1_drift <= 80:
            group.append(block)
        else:
            protect_table_group(group, page_rect)
            group = [block]
    protect_table_group(group, page_rect)


def compact_table_line_candidate(block):
    rect = block["rect"]
    text = normalize_text(block.get("text", ""))
    if not text or block.get("protected"):
        return False
    if block["font_size"] > 10.8 or rect.height > 36:
        return False
    if rect.width < 80:
        return False

    words = re.findall(r"[A-Za-z]{2,}", text)
    digit_count = sum(1 for char in text if char.isdigit())
    table_terms = ("bleu", "flops", "model", "training cost", "en-de", "en-fr")
    has_table_term = any(term in text.lower() for term in table_terms)
    has_numeric_columns = digit_count >= 2 and bool(re.search(r"\b\d+(?:\.\d+)?\b.*\b\d+(?:\.\d+)?\b", text))
    has_scientific_cost = bool(re.search(r"\d+(?:\.\d+)?\s*[·x×]\s*10", text))
    return has_table_term or has_numeric_columns or has_scientific_cost or len(words) <= 10


def protect_table_group(group, page_rect):
    if len(group) < 4:
        return

    rect = fitz.Rect(group[0]["rect"])
    for block in group[1:]:
        rect |= block["rect"]

    if rect.width > page_rect.width * 0.82:
        return
    if rect.height > page_rect.height * 0.35:
        return

    numeric_rows = sum(1 for block in group if sum(1 for char in block["text"] if char.isdigit()) >= 2)
    table_terms = sum(
        1
        for block in group
        if any(term in block["text"].lower() for term in ("bleu", "flops", "model", "en-de", "en-fr"))
    )
    if numeric_rows < 2 and table_terms < 2:
        return

    for index, block in enumerate(group):
        if index == 0 and looks_like_table_caption(block.get("text", "")):
            continue
        block["protected"] = True


def looks_like_table_caption(text):
    return bool(re.match(r"^(?:Table|Figure)\s+\d+\s*[:.]", normalize_text(text), re.IGNORECASE))


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
        merged.append(merge_drop_cap_group(group))

    return sorted(merged, key=lambda item: (item["rect"].y0, item["rect"].x0))


def drop_cap_body_indexes(candidate, blocks, candidate_index, consumed):
    text = candidate["text"].strip()
    if len(text) > 2 or not re.match(r"^[A-Za-z]$", text):
        return []

    rect = candidate["rect"]
    if rect.height < max(24, candidate["font_size"] * 0.95):
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
        body_text = block["text"].strip()
        if not body_text:
            continue
        if not re.match(r"^[a-z]", body_text):
            continue

        vertical_overlap = min(rect.y1, other.y1) - max(rect.y0, other.y0)
        close_below = 0 <= other.y0 - rect.y1 <= rect.height * 0.35
        if vertical_overlap > 0 or close_below:
            nearby.append(index)

    nearby.sort(key=lambda item: (blocks[item]["rect"].y0, blocks[item]["rect"].x0))
    return nearby[:2]


def merge_drop_cap_group(group):
    drop_cap = group[0]
    body_blocks = sorted(group[1:], key=lambda item: (item["rect"].y0, item["rect"].x0))
    rect = fitz.Rect(drop_cap["rect"])
    for block in body_blocks:
        rect |= block["rect"]

    first_body_text = body_blocks[0]["text"] if body_blocks else ""
    remaining_texts = [block["text"] for block in body_blocks[1:]]
    text_parts = [f"{drop_cap['text'].strip()}{first_body_text.strip()}"] + remaining_texts
    font_sizes = [block["font_size"] for block in body_blocks] or [drop_cap["font_size"]]
    bold_count = sum(1 for block in body_blocks if block.get("bold", False))

    return {
        "text": normalize_text(" ".join(text_parts)),
        "rect": rect,
        "erase_rects": [erase_rect for block in group for erase_rect in block["erase_rects"]],
        "font_size": sum(font_sizes) / len(font_sizes),
        "bold": bold_count >= max(1, len(body_blocks) // 2) if body_blocks else False,
        "title": any(block.get("title", False) for block in body_blocks),
        "protected": any(block.get("protected", False) for block in body_blocks),
    }


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
    target_language = normalized_target_language(settings)
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
    translatable, math_replacements_by_id = prepare_translatable_blocks(blocks, settings)
    return translate_prepared_page(translatable, math_replacements_by_id, settings, page_number)


def prepare_translatable_blocks(blocks, settings):
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
    return translatable, math_replacements_by_id


def translate_prepared_page(translatable, math_replacements_by_id, settings, page_number):
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
    untranslated = []
    for item in items:
        source = item["text"]
        translated = translations.get(item["id"], "")
        if not translated.strip():
            untranslated.append(item["id"])
            continue
        if english_word_count(source) < 8 and not contains_cjk_compatible_text(source):
            continue
        if looks_like_name_or_affiliation_block(source):
            continue
        if looks_untranslated_for_target(source, translated, settings):
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

    if any(contains_target_language_script(text, settings) for text in inserted_texts):
        return True

    emit_warning(page_number, f"Page {page_number} has prose but no {normalized_target_language(settings)} translation was written.")
    return False


def looks_untranslated_for_target(source, translated, settings):
    if looks_like_garbled_translation(translated, settings):
        return True
    if target_is_cjk(settings):
        if english_word_count(source) < 8:
            return False
        if looks_like_name_or_affiliation_block(source):
            return False
        return not contains_target_language_script(translated, settings)
    if target_is_latin_language(settings):
        target_language = normalized_target_language(settings).lower()
        if not contains_target_language_script(translated, settings):
            return True
        if contains_cjk_compatible_text(source):
            translated_cjk = cjk_char_count(translated)
            translated_words = english_word_count(translated)
            return translated_cjk >= 2 and translated_cjk > translated_words * 2
        if target_language in {"spanish", "french"} and english_word_count(source) >= 8:
            return normalized_for_language_compare(source) == normalized_for_language_compare(translated)
    return False


def translate_blocks_as_page(items, settings, page_number):
    target_language = normalized_target_language(settings)
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


def add_original_text_redactions(page, block):
    added = False
    for erase_rect in block["erase_rects"]:
        safe_rect = fitz.Rect(erase_rect)
        if not valid_text_rect(safe_rect):
            continue
        safe_rect.x0 -= 1.0
        safe_rect.x1 += 1.0
        safe_rect.y0 -= 0.5
        safe_rect.y1 += 0.5
        page.add_redact_annot(safe_rect, fill=(1, 1, 1), cross_out=False)
        added = True
    return added


def apply_original_text_redactions(page):
    page.apply_redactions(
        images=fitz.PDF_REDACT_IMAGE_NONE,
        graphics=fitz.PDF_REDACT_LINE_ART_NONE,
        text=fitz.PDF_REDACT_TEXT_REMOVE,
    )


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
    out_doc.insert_pdf(source_doc, from_page=page_index, to_page=page_index, links=0)


def append_translation_page(out_doc, source_doc, page_index):
    out_doc.insert_pdf(source_doc, from_page=page_index, to_page=page_index, links=0)
    return out_doc[-1]


def output_page_index(source_page_index, start_index, translated=False):
    return (source_page_index - start_index) * 2 + (1 if translated else 0)


def mapped_internal_link(link, start_index, end_index, translated=False):
    target_page = link.get("page")
    if target_page is None or target_page < start_index or target_page >= end_index:
        return None
    mapped = {
        "kind": fitz.LINK_GOTO,
        "from": link.get("from"),
        "page": output_page_index(target_page, start_index, translated=translated),
    }
    if "to" in link:
        mapped["to"] = link["to"]
    if "zoom" in link:
        mapped["zoom"] = link["zoom"]
    return mapped


def mapped_external_link(link):
    mapped = dict(link)
    mapped.pop("xref", None)
    mapped.pop("id", None)
    return mapped


def copy_source_page_links(out_doc, source_doc, page_index, start_index, end_index):
    out_page = out_doc[output_page_index(page_index, start_index, translated=False)]
    for link in source_doc[page_index].get_links():
        mapped = link_for_output(link, start_index, end_index, translated=False)
        if mapped is not None:
            out_page.insert_link(mapped)


def copy_translation_page_links(out_doc, source_doc, page_index, start_index, end_index, insertion_map):
    out_page = out_doc[output_page_index(page_index, start_index, translated=True)]
    for link in source_doc[page_index].get_links():
        mapped = link_for_output(link, start_index, end_index, translated=True)
        if mapped is None:
            continue
        mapped["from"] = mapped_translation_link_rect(link.get("from"), insertion_map)
        if valid_text_rect(fitz.Rect(mapped["from"])):
            out_page.insert_link(mapped)


def link_for_output(link, start_index, end_index, translated=False):
    kind = link.get("kind")
    if link.get("page") is not None:
        return mapped_internal_link(link, start_index, end_index, translated=translated)
    if kind in {fitz.LINK_URI, fitz.LINK_GOTOR, fitz.LINK_LAUNCH}:
        return mapped_external_link(link)
    return None


def mapped_translation_link_rect(link_rect, insertion_map):
    if not link_rect:
        return link_rect
    source_rect = fitz.Rect(link_rect)
    best = None
    best_score = 0
    for source_block_rect, translated_rect in insertion_map:
        overlap = rect_overlap_area(source_rect, source_block_rect)
        if overlap > best_score:
            best_score = overlap
            best = translated_rect
    if best is not None and best_score > 0:
        return best
    return source_rect


def rect_overlap_area(first, second):
    rect = fitz.Rect(first)
    rect &= fitz.Rect(second)
    if rect.is_empty:
        return 0
    return rect.width * rect.height


def rebuild_output_links(out_doc, source_doc, page_indices, start_index, end_index, insertion_maps_by_page):
    for page_index in page_indices:
        copy_source_page_links(out_doc, source_doc, page_index, start_index, end_index)
        copy_translation_page_links(
            out_doc,
            source_doc,
            page_index,
            start_index,
            end_index,
            insertion_maps_by_page.get(page_index, []),
        )


def write_translation_page(out_doc, source_doc, page_index, blocks, translations, settings, start_index, end_index):
    append_source_page(out_doc, source_doc, page_index)
    page = append_translation_page(out_doc, source_doc, page_index)
    pending_insertions = []
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
            pending_insertions.append((block, rect, font_size, translated))
        elif target_is_cjk(settings) and english_word_count(block.get("text", "")) >= 8:
            emit_warning(page_index + 1, f"Block {block['id']} translation did not fit; original text kept.")

    has_redactions = False
    for block, _, _, _ in pending_insertions:
        has_redactions = add_original_text_redactions(page, block) or has_redactions
    if has_redactions:
        apply_original_text_redactions(page)

    insertion_map = []
    for block, rect, font_size, translated in pending_insertions:
        insert_translation_with_style(page, rect, font_size, translated, bold=block.get("bold", False))
        inserted_texts.append(translated)
        insertion_map.append((fitz.Rect(block["rect"]), fitz.Rect(rect)))

    validate_written_page(blocks, inserted_texts, settings, page_index + 1)
    return insertion_map


def translate_pdf(input_path, output_path, settings, start_page, page_limit):
    source_doc = fitz.open(input_path)
    out_doc = fitz.open()
    try:
        start_index, end_index = page_range(source_doc, start_page, page_limit)
        pages = extract_page_blocks(source_doc, input_path, start_index, end_index, settings)
        translations_by_page = translate_pages(pages, settings)
        insertion_maps_by_page = {}
        for page_index, blocks in pages:
            insertion_maps_by_page[page_index] = write_translation_page(
                out_doc,
                source_doc,
                page_index,
                blocks,
                translations_by_page.get(page_index, {}),
                settings,
                start_index,
                end_index,
            )
            print(json.dumps({"page": page_index + 1, "status": "done"}, ensure_ascii=False), flush=True)
        rebuild_output_links(
            out_doc,
            source_doc,
            [page_index for page_index, _ in pages],
            start_index,
            end_index,
            insertion_maps_by_page,
        )
        out_doc.save(output_path, garbage=4, deflate=True)
    finally:
        out_doc.close()
        source_doc.close()


def extract_page_blocks(source_doc, input_path, start_index, end_index, settings):
    if should_use_opendataloader(settings):
        try:
            return opendataloader_adapter.extract_page_blocks(input_path, start_index, end_index)
        except Exception as exc:
            emit_warning(start_index + 1, f"OpenDataLoader extraction failed; using PyMuPDF extraction: {exc}")

    pages = []
    for page_index in range(start_index, end_index):
        pages.append((page_index, text_blocks(source_doc[page_index])))
    return pages


def should_use_opendataloader(settings):
    configured = str(settings.get("parserBackend", "")).strip().lower()
    environment = os.environ.get("LEAFTRANSLATE_PARSER", "").strip().lower()
    if configured == "pymupdf" or environment == "pymupdf":
        return False
    return opendataloader_adapter is not None


def translate_pages(pages, settings):
    max_workers = page_concurrency(settings, len(pages))
    if max_workers == 1:
        translations_by_page = {}
        for page_index, blocks in pages:
            translations, _ = translate_page_with_cache(page_index, blocks, settings)
            translations_by_page[page_index] = translations
        return translations_by_page

    translations_by_page = {}
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(translate_page_with_cache, page_index, blocks, settings): page_index
            for page_index, blocks in pages
        }
        for future in as_completed(futures):
            page_index = futures[future]
            translations, used_cache = future.result()
            translations_by_page[page_index] = translations
            if not used_cache:
                print(
                    json.dumps(
                        {"page": page_index + 1, "status": "translated"},
                        ensure_ascii=False,
                    ),
                    flush=True,
                )
    return translations_by_page


def translate_page_with_cache(page_index, blocks, settings):
    page_number = page_index + 1
    translatable, math_replacements_by_id = prepare_translatable_blocks(blocks, settings)
    cached = load_cached_page_translations(settings, page_number, translatable)
    if cached is not None:
        print(
            json.dumps(
                {"page": page_number, "status": "cache"},
                ensure_ascii=False,
            ),
            flush=True,
        )
        return cached, True

    translations = translate_prepared_page(translatable, math_replacements_by_id, settings, page_number)
    invalid_ids = invalid_translation_ids(translatable, translations, settings)
    if invalid_ids:
        emit_warning(page_number, f"Page not cached because translated ids do not match target language: {invalid_ids}")
    else:
        save_cached_page_translations(settings, page_number, translatable, translations)
    return translations, False


def load_cached_page_translations(settings, page_number, translatable):
    path = page_cache_path(settings, page_number)
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as file:
            payload = json.load(file)
        if payload.get("settingsSignature") != cache_settings_signature(settings):
            return None
        if payload.get("source") != translatable:
            return None
        translations = payload.get("translations", {})
        normalized = {int(key): str(value) for key, value in translations.items()}
        expected_ids = {item["id"] for item in translatable}
        if expected_ids - set(normalized.keys()):
            return None
        if invalid_translation_ids(translatable, normalized, settings):
            return None
        return normalized
    except Exception as exc:
        emit_warning(page_number, f"Ignoring unreadable cache: {exc}")
        return None


def save_cached_page_translations(settings, page_number, translatable, translations):
    path = page_cache_path(settings, page_number)
    if not path:
        return
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        payload = {
            "page": page_number,
            "settingsSignature": cache_settings_signature(settings),
            "source": translatable,
            "translations": {str(key): value for key, value in translations.items()},
        }
        temp_path = f"{path}.tmp"
        with open(temp_path, "w", encoding="utf-8") as file:
            json.dump(payload, file, ensure_ascii=False)
        os.replace(temp_path, path)
    except Exception as exc:
        emit_warning(page_number, f"Failed to write cache: {exc}")


def page_cache_path(settings, page_number):
    cache_directory = settings.get("cacheDirectory")
    if not cache_directory:
        return None
    return os.path.join(cache_directory, cache_language_key(settings), f"page-{page_number}.json")


def cache_settings_signature(settings):
    return {
        "version": 2,
        "provider": settings.get("provider", ""),
        "endpoint": settings.get("endpoint", ""),
        "model": settings.get("model", ""),
        "targetLanguage": normalized_target_language(settings),
    }


def cache_language_key(settings):
    target_language = normalized_target_language(settings).lower()
    return re.sub(r"[^a-z0-9_-]+", "-", target_language).strip("-") or "language"


def page_concurrency(settings, page_count):
    configured = int(settings.get("pageConcurrency", Heuristics.PAGE_CONCURRENCY))
    capped = min(configured, Heuristics.PAGE_CONCURRENCY_LIMIT)
    return max(1, min(capped, page_count))


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
