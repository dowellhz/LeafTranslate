# LeafTranslate

A native macOS prototype for translating PDF files into bilingual documents.

## Stack

- Swift
- CGPDFDocument for PDF parsing
- WKWebView for HTML preview
- NSPrintOperation / WKWebView printing for PDF export

## Workflow

1. Open a PDF.
2. Configure an OpenAI-compatible LLM endpoint, model, token, and target language.
3. Translate paragraphs.
4. Preview bilingual HTML: each source paragraph is followed by its translation.
5. Export the preview as a new PDF.

## Build

```bash
./build.sh
open LeafTranslate.app
```

## Notes

This is a prototype. PDF text extraction uses low-level CGPDF scanning, which works for many text PDFs but will not perfectly reconstruct every layout. Image extraction is represented as placeholders in reading order; accurate image extraction and positioning can be added next by walking page XObjects and rendering extracted image streams.
