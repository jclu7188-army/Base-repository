# Google Docs API v1 reference (plus the Drive endpoints Docs rely on)

Docs API base: `https://docs.googleapis.com/v1`. Drive base: `https://www.googleapis.com/drive/v3`
and `https://www.googleapis.com/upload/drive/v3` for content uploads. Auth: bearer token.

| Scope | Allows |
|-------|--------|
| `https://www.googleapis.com/auth/documents.readonly` | `documents.get` |
| `https://www.googleapis.com/auth/documents` | get, create, batchUpdate |
| `https://www.googleapis.com/auth/drive.file` | Drive calls on files the app created/opened |
| `https://www.googleapis.com/auth/drive` | all Drive calls (export, convert, comments, share) |

## Table of contents

- Endpoints
- Document JSON model
- Indexes and ranges
- batchUpdate request catalog
- Export MIME types (Drive)
- Import / conversion (Drive)
- Revisions and comments (Drive)

## Endpoints

| Method | Path | Notes |
|--------|------|-------|
| GET | `/v1/documents/{documentId}?includeTabsContent=true&suggestionsViewMode=` | Whole document. `suggestionsViewMode`: `DEFAULT_FOR_CURRENT_ACCESS`, `SUGGESTIONS_INLINE`, `PREVIEW_SUGGESTIONS_ACCEPTED`, `PREVIEW_WITHOUT_SUGGESTIONS`. |
| POST | `/v1/documents` | `{title}` → new empty Doc in My Drive root. Move it with Drive `files.update` `addParents`. |
| POST | `/v1/documents/{documentId}:batchUpdate` | `{requests:[…], writeControl:{requiredRevisionId?}}`. Atomic: any invalid request fails the batch. Returns `{replies:[…], writeControl}`. |

## Document JSON model

```
document
├─ documentId, title, revisionId
├─ tabs[]                          (present when includeTabsContent=true)
│   ├─ tabProperties {tabId, title, index}
│   └─ documentTab {body, headers, footers, footnotes, documentStyle, namedStyles, lists, inlineObjects}
├─ body.content[]                  structural elements (legacy single-tab view)
│   ├─ {startIndex, endIndex, sectionBreak}
│   ├─ {startIndex, endIndex, paragraph}
│   │    ├─ paragraphStyle {namedStyleType, alignment, headingId, indentStart, spacingMode, ...}
│   │    ├─ bullet {listId, nestingLevel}
│   │    └─ elements[]  {startIndex, endIndex, textRun {content, textStyle}}
│   │                   | inlineObjectElement {inlineObjectId} | footnoteReference | pageBreak
│   │                   | horizontalRule | richLink | person | dateElement
│   ├─ {startIndex, endIndex, table {rows, columns, tableRows[] {tableCells[] {content[]}}}}
│   └─ {startIndex, endIndex, tableOfContents {content[]}}
├─ headers{}, footers{}, footnotes{}
├─ documentStyle {pageSize, marginTop, ...}
├─ namedStyles {styles[] {namedStyleType, textStyle, paragraphStyle}}
├─ lists {listId: {listProperties {nestingLevels[]}}}
├─ inlineObjects {id: {inlineObjectProperties {embeddedObject {imageProperties {contentUri}, size}}}}
└─ namedRanges {name: {namedRanges[] {namedRangeId, ranges[]}}}
```

Extract plain text with jq:

```bash
jq -r '[.. | .textRun? | select(.) | .content] | join("")' doc.json
```

`textStyle` fields: `bold`, `italic`, `underline`, `strikethrough`, `smallCaps`,
`backgroundColor`, `foregroundColor {color {rgbColor {red, green, blue}}}`, `fontSize {magnitude,
unit: "PT"}`, `weightedFontFamily {fontFamily, weight}`, `baselineOffset`, `link {url |
bookmarkId | headingId}`.

`namedStyleType` values: `NORMAL_TEXT`, `TITLE`, `SUBTITLE`, `HEADING_1` … `HEADING_6`.

## Indexes and ranges

- Indexes count **UTF-16 code units** from the start of the body segment; the body starts at 1
  (index 0 is the implicit section break). Emoji and many CJK characters count as 2.
- Every paragraph ends with `\n`, included in its range. The document's final newline cannot be
  deleted or replaced — insert at `endIndex - 1` of the last element to append.
- A `range` is `{startIndex, endIndex, segmentId?, tabId?}`. Omit `segmentId` for the body; use
  a header/footer/footnote id to target those.
- After each insertion or deletion, later indexes move. In one `batchUpdate`, requests are
  applied in order, so **sort edits by descending index** or use index-free requests
  (`replaceAllText`, `replaceNamedRangeContent`).
- Ranges must not straddle structural boundaries (e.g. from a paragraph into a table cell).

## batchUpdate request catalog

Text:

```json
{"insertText": {"location": {"index": 1, "tabId": "t.0"}, "text": "Hello\n"}}
{"insertText": {"endOfSegmentLocation": {"segmentId": ""}, "text": "Appended\n"}}
{"deleteContentRange": {"range": {"startIndex": 5, "endIndex": 12}}}
{"replaceAllText": {"containsText": {"text": "{{NAME}}", "matchCase": true}, "replaceText": "Ada"}}
```

Styling:

```json
{"updateTextStyle": {"range": {"startIndex": 1, "endIndex": 6},
  "textStyle": {"bold": true, "link": {"url": "https://example.com"}}, "fields": "bold,link"}}
{"updateParagraphStyle": {"range": {"startIndex": 1, "endIndex": 6},
  "paragraphStyle": {"namedStyleType": "HEADING_1", "alignment": "CENTER"}, "fields": "namedStyleType,alignment"}}
{"createParagraphBullets": {"range": {"startIndex": 1, "endIndex": 40}, "bulletPreset": "BULLET_DISC_CIRCLE_SQUARE"}}
{"deleteParagraphBullets": {"range": {"startIndex": 1, "endIndex": 40}}}
```

`fields` is a mask naming the properties you set; omitting it is an error. Bullet presets:
`BULLET_DISC_CIRCLE_SQUARE`, `BULLET_ARROW_DIAMOND_DISC`, `BULLET_CHECKBOX`,
`NUMBERED_DECIMAL_ALPHA_ROMAN`, `NUMBERED_DECIMAL_NESTED`, and more. Nesting = leading tabs in
the inserted text.

Structure:

```json
{"insertTable": {"rows": 3, "columns": 2, "location": {"index": 20}}}
{"insertTableRow": {"tableCellLocation": {"tableStartLocation": {"index": 21}, "rowIndex": 0, "columnIndex": 0}, "insertBelow": true}}
{"deleteTableRow": {"tableCellLocation": {"tableStartLocation": {"index": 21}, "rowIndex": 1, "columnIndex": 0}}}
{"insertPageBreak": {"location": {"index": 20}}}
{"insertSectionBreak": {"location": {"index": 20}, "sectionType": "NEXT_PAGE"}}
{"insertInlineImage": {"location": {"index": 20}, "uri": "https://example.com/img.png",
  "objectSize": {"width": {"magnitude": 300, "unit": "PT"}}}}
{"createHeader": {"type": "DEFAULT"}}      {"createFooter": {"type": "DEFAULT"}}
{"createFootnote": {"location": {"index": 20}}}
{"createNamedRange": {"name": "summary", "range": {"startIndex": 1, "endIndex": 40}}}
{"replaceNamedRangeContent": {"namedRangeName": "summary", "text": "New summary\n"}}
{"updateDocumentStyle": {"documentStyle": {"marginTop": {"magnitude": 36, "unit": "PT"}}, "fields": "marginTop"}}
```

Table cells: a freshly inserted table's first cell content starts at `tableStartIndex + 3`
(table, row, cell each add an index); re-fetch the document rather than computing offsets.

Concurrency: pass `writeControl.requiredRevisionId` (from `documents.get`) to fail instead of
clobbering if someone edited in between.

## Export MIME types (Drive)

`GET /drive/v3/files/{id}/export?mimeType=…` (10 MB limit; use `exportLinks` from
`files.get?fields=exportLinks` for larger).

| Format | MIME |
|--------|------|
| Markdown | `text/markdown` |
| Plain text | `text/plain` |
| HTML | `text/html` (zipped with images: `application/zip`) |
| Word | `application/vnd.openxmlformats-officedocument.wordprocessingml.document` |
| PDF | `application/pdf` |
| RTF | `application/rtf` |
| OpenDocument | `application/vnd.oasis.opendocument.text` |
| EPUB | `application/epub+zip` |

## Import / conversion (Drive)

Create a Doc from content: `POST /upload/drive/v3/files?uploadType=multipart` with metadata
`{"name": "…", "mimeType": "application/vnd.google-apps.document", "parents": ["…"]}` and a
content part whose `Content-Type` is the source format. Supported sources: `text/markdown`,
`text/plain`, `text/html`, `application/rtf`, `.docx`, `.odt`, `.doc`. Markdown import keeps
headings, emphasis, links, lists, tables, code blocks, and images by URL.

Replace an existing Doc's body: `PATCH /upload/drive/v3/files/{id}?uploadType=media` with the
same source `Content-Type`. Keeps the file ID and sharing; comment anchors are lost.

Copy a Doc (e.g. instantiate a template): `POST /drive/v3/files/{id}/copy` with `{"name": "…",
"parents": ["…"]}`, then `batchUpdate` with `replaceAllText` for placeholders.

## Revisions and comments (Drive)

| Method | Path | Notes |
|--------|------|-------|
| GET | `/drive/v3/files/{id}/revisions?fields=revisions(id,modifiedTime,lastModifyingUser/displayName)` | Docs keep revisions automatically |
| GET | `/drive/v3/files/{id}/export?mimeType=…` | Latest only; older revisions via `revisions/{revId}?alt=media` are for binary files |
| GET | `/drive/v3/files/{id}/comments?fields=comments(id,content,author/displayName,createdTime,resolved,quotedFileContent/value,anchor,replies(content,author/displayName))&includeDeleted=false` | Page with `pageToken` |
| POST | `/drive/v3/files/{id}/comments?fields=id` | `{content}` (unanchored) |
| POST | `/drive/v3/files/{id}/comments/{cid}/replies?fields=id` | `{content}` or `{action: "resolve"}` |
| PATCH | `/drive/v3/files/{id}/comments/{cid}` | `{resolved: true}` |
| DELETE | `/drive/v3/files/{id}/comments/{cid}` | |
