#!/usr/bin/env python3
import sys

try:
    import fitz
except Exception as exc:
    print(f"PyMuPDF is not available: {exc}", file=sys.stderr)
    sys.exit(1)


def output_page_index(source_page_index):
    return (source_page_index - 1) // 2


def map_link(link, source_page_count):
    if link.get("page") is not None:
        target_page = link.get("page")
        if target_page is None or target_page < 0 or target_page >= source_page_count:
            return None
        if target_page % 2 == 0:
            return None
        mapped = {
            "kind": fitz.LINK_GOTO,
            "from": link.get("from"),
            "page": output_page_index(target_page),
        }
        if "to" in link:
            mapped["to"] = link["to"]
        if "zoom" in link:
            mapped["zoom"] = link["zoom"]
        return mapped
    mapped = dict(link)
    mapped.pop("xref", None)
    mapped.pop("id", None)
    return mapped


def export_translation_only(source_path, output_path):
    source_doc = fitz.open(source_path)
    output_doc = fitz.open()
    try:
        translation_pages = list(range(1, source_doc.page_count, 2))
        for page_index in translation_pages:
            output_doc.insert_pdf(source_doc, from_page=page_index, to_page=page_index, links=0)

        for page_index in translation_pages:
            output_page = output_doc[output_page_index(page_index)]
            for link in source_doc[page_index].get_links():
                mapped = map_link(link, source_doc.page_count)
                if mapped is not None:
                    output_page.insert_link(mapped)

        if output_doc.page_count == 0:
            raise RuntimeError("No translation pages found.")
        output_doc.save(output_path, garbage=4, deflate=True)
    finally:
        output_doc.close()
        source_doc.close()


def main():
    if len(sys.argv) != 3:
        raise RuntimeError("Usage: export_translation_only.py input-bilingual.pdf output.pdf")
    export_translation_only(sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
