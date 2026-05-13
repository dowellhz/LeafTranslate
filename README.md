# LeafTranslate

LeafTranslate is a native macOS app for translating PDF documents with an OpenAI-compatible LLM API. It keeps the original PDF pages, creates translated pages, and exports a bilingual PDF or a translation-only PDF.

## Features

- Open and preview PDF documents on macOS.
- Translate selected page ranges instead of forcing a full-document run.
- Support target languages: Chinese, English, Spanish, French, Japanese, and Korean.
- Support OpenAI-compatible providers, including DeepSeek and custom/Azure-style endpoints.
- Cache translation results per book, page, model settings, and target language.
- Clear the cache for the currently opened book.
- Run page-level translation with limited concurrency for better speed while reducing API pressure.
- Export bilingual PDFs with original and translated pages interleaved.
- Export translation-only PDFs.
- Preserve images, formulas, and dense table regions where possible.
- Rebuild internal PDF links so original pages link to original targets and translated pages link to translated targets.
- Preserve URL links in exported PDFs.
- Use the current system language for Chinese or English interface text.
- Provide a signed and notarized macOS installer package.

## Install

Download the latest installer from GitHub Releases:

```text
https://github.com/dowellhz/LeafTranslate/releases
```

The installer places the app at:

```text
/Applications/LeafTranslate.app
```

## Usage

1. Open a PDF.
2. Choose the model provider and target language.
3. Enter your API token.
4. Set the start and end pages.
5. Click Translate.
6. Review the generated bilingual preview.
7. Export either:
   - Bilingual PDF
   - Translation-only PDF

If the end page exceeds the source PDF page count, LeafTranslate clamps it back to the maximum source page.

## API Configuration

For built-in providers, only the required fields are shown.

For custom providers, configure:

- API URL
- Model or Azure deployment name
- API token

Azure-compatible endpoints can be used through the custom provider when the endpoint follows an OpenAI-compatible chat or responses API shape.

## Cache

LeafTranslate computes a book hash and stores page translations under Application Support. Cache entries are separated by target language and model settings, so translating the same book into different languages does not mix results.

The sidebar cache button clears cache for the currently opened book.

## Build From Source

```bash
./build.sh
open LeafTranslate.app
```

The app bundles Python resources used for PDF translation and PyMuPDF-based export handling.

## Release Package

The macOS installer is built as a Developer ID signed package and submitted to Apple notarization.

Current release package:

```text
release/pkg/LeafTranslate-1.0.0.pkg
```

## Known Limitations

PDF layout reconstruction is difficult. LeafTranslate uses conservative heuristics to protect images, formulas, tables, and chart labels, but complex PDFs can still have layout issues. Some protected text may remain untranslated to avoid breaking figures or formulas.

Partial page-range exports can only preserve internal links whose target pages are included in the exported range. Links pointing outside the selected range are skipped because the target page does not exist in the output PDF.
