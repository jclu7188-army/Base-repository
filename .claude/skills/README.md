# Project skills

Skills in this directory are loaded automatically by Claude Code for this repository.

| Skill  | Purpose                                                                 |
|--------|-------------------------------------------------------------------------|
| `docx` | Create, read, edit Word documents (.docx/.dotx), tracked changes, comments |
| `pptx` | Create, read, edit PowerPoint decks (.pptx/.potx), templates, notes     |
| `xlsx` | Create, read, edit spreadsheets (.xlsx/.xlsm/.csv), formulas, charts    |
| `pdf`  | Read, merge, split, rotate, watermark, fill forms, OCR PDFs             |

## Source

Copied from Anthropic's public skills repository:
https://github.com/anthropics/skills (`skills/` directory, commit `33375500bcea98d610eb30ce10ac4e59b89c390d`).

Each skill keeps its own `LICENSE.txt`; third-party attributions are in `THIRD_PARTY_NOTICES.md`.

## Runtime dependencies

The skills call helper scripts that need tools installed in the session. See each
`SKILL.md` for details. Common ones:

- Python: `python-docx`, `openpyxl`, `python-pptx`, `pypdf`, `pdfplumber`, `reportlab`, `pytesseract`, `pdf2image`
- Node: `docx`, `pptxgenjs`
- System: LibreOffice (`soffice`), `pdftotext`/`qpdf` (poppler), `tesseract`

## Updating

Re-clone the source repo and copy the `skills/<name>` directories over these.
