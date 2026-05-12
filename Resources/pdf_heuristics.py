import os
import re


class Heuristics:
    CJK_TARGET_NAMES = ("chinese", "中文", "zh", "cn")
    AFFILIATION_TERMS = ("university", "institute", "school of", "department", "laboratory")
    AUTHOR_PROSE_TERMS = {"the", "and", "for", "with", "from", "that", "this", "which", "into", "rather", "than"}
    DOCUMENT_MARKER_PREFIXES = ("arxiv:", "doi:", "isbn:")
    DOCUMENT_MARKER_PATTERN = re.compile(r"\d{4}|arxiv|cs\.", re.IGNORECASE)
    TOC_DOT_LEADER_PATTERN = re.compile(r"\.{2,}\s*\d+\s*$")
    TOC_NUMBERED_ENTRY_PATTERN = re.compile(r"^\d+(?:\.\d+)*\s+\S.+\s+\d+\s*$")
    FORMULA_WORDS = {"Softmax", "Sigmoid", "RMSNorm", "Topk", "CrossEntropy", "FFN", "TRM"}
    MATH_CHARS = set("=<>≤≥±∓×÷∑∏√∫∞≈≠∈∉⊂⊃⊆⊇∪∩∂∇→←↔⇒⇔αβγδλμσπθΩ∆")
    TECHNICAL_TERMS_FOR_SPACING = ("PP", "TP", "EP", "DP", "MTP", "Nc", "FP8", "BF16", "FP32")
    GARBLED_QUESTION_MIN_COUNT = 4
    GARBLED_QUESTION_RATIO = 0.12
    MATH_FRAGMENT_MAX_LENGTH = 90
    LAYOUT_FIT_ATTEMPTS = 6
    LAYOUT_FONT_SHRINK = 0.9
    LAYOUT_BOX_GROWTH = 24
    TRANSLATE_TOC_DEFAULT = False
    FALLBACK_CONCURRENCY = 3


CJK_FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/System/Library/Fonts/STHeiti Light.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/Supplemental/Songti.ttc",
]
CJK_FONT_FILE = next((path for path in CJK_FONT_CANDIDATES if os.path.exists(path)), None)

CJK_BOLD_FONT_CANDIDATES = [
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
]
CJK_BOLD_FONT_FILE = next((path for path in CJK_BOLD_FONT_CANDIDATES if os.path.exists(path)), CJK_FONT_FILE)
