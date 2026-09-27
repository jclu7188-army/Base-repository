# Project skills

Skills in this directory are loaded automatically by Claude Code for this repository.

| Skill  | Purpose                                                                 |
|--------|-------------------------------------------------------------------------|
| `docx` | Create, read, edit Word documents (.docx/.dotx), tracked changes, comments |
| `pptx` | Create, read, edit PowerPoint decks (.pptx/.potx), templates, notes     |
| `xlsx` | Create, read, edit spreadsheets (.xlsx/.xlsm/.csv), formulas, charts    |
| `pdf`  | Read, merge, split, rotate, watermark, fill forms, OCR PDFs             |
| `google-drive-api` | Search, read, upload, move, share files in Google Drive (Docs, Sheets, Slides export) |
| `gmail` | Search, read, draft, send, reply, label, archive Gmail                  |
| `google-docs` | Read, create, edit (batchUpdate), export, comment on Google Docs   |
| `playwright` | Headless browsing, scraping, screenshots, e2e tests with Playwright; `browse.cjs` CLI |
| `chrome-devtools` | Launch Chrome with a DevTools port, CDP recipes, Chrome DevTools MCP server |
| `claude-in-chrome-setup` | Install/connect the Claude in Chrome extension, `--chrome`, `/chrome`, which browser path applies |
| `chrome-browser` | Driving the user's Chrome through the Claude in Chrome extension tools |
| `built-in-browser` | Driving the Claude desktop app's built-in browser pane |
| `computer-use` | Desktop control through the Claude desktop app |
| `webapp-testing` | Testing local web apps with Python Playwright; `with_server.py` helper |

## Sources

- `docx`, `pptx`, `xlsx`, `pdf`: copied from https://github.com/anthropics/skills
  (`skills/` directory, commit `33375500bcea98d610eb30ce10ac4e59b89c390d`). Proprietary
  licence; see each skill's `LICENSE.txt` and `THIRD_PARTY_NOTICES.md`.
- `google-drive-api`: copied from https://github.com/anthropics/claude-tag-plugins
  (`google-drive/skills/google-drive-api`, commit `034af83830ff459baeca6feaaa25a0297eb942e2`),
  Apache-2.0 (`LICENSE.txt`, `NOTICE.txt` in the skill). A "Connector tools" section was
  appended locally.
- `gmail`, `google-docs`: written for this repository in the same style as the Drive skill
  (REST recipes, bundled `curl` + `jq` scripts, API reference). Their scripts were tested
  against a local mock of the Google APIs, not against live accounts.
- `webapp-testing`: copied from https://github.com/anthropics/skills (same commit as the
  Office skills). Proprietary licence in `LICENSE.txt`.
- `chrome-browser`, `built-in-browser`, `computer-use`: Anthropic's bundled browser skills as
  synced into Claude Code sessions (proprietary licence in each `LICENSE.txt`). They describe
  tools that exist only when the matching browser is connected to the session.
- `playwright`, `chrome-devtools`, `claude-in-chrome-setup`: written for this repository.
  Facts about Claude in Chrome come from https://code.claude.com/docs/en/chrome; MCP server
  options from the chrome-devtools-mcp and playwright-mcp READMEs. Scripts were run in this
  container against the pre-installed Chromium.

## Google skills: how they authenticate

The three Google skills work in two modes:

1. **Connector tools** (`mcp__Gmail__*`, `mcp__Google_Drive__*`) when a Gmail or Google Drive
   connector is attached to the session (Claude Code on the web, Cowork). Nothing to configure;
   this is the recommended path.
2. **REST + scripts** when `GOOGLE_ACCESS_TOKEN` is set in the environment to an OAuth 2.0
   access token with the needed scopes (Drive, Gmail, Docs). Claude Code does not inject this
   token; obtain one yourself (e.g. `gcloud auth print-access-token` with the right scopes, or
   an OAuth playground token) and export it before the session, ideally via the environment's
   secrets rather than a file in the repo.

Without either, the skills stop and say so rather than guessing credentials.

## Browser tooling

The repository root carries the runtime the browser skills rely on (see the root `README.md`):
`package.json` (Playwright 1.56.1, `@playwright/test`, `chrome-devtools-mcp`, `@playwright/mcp`),
`playwright.config.ts` + `e2e/`, `scripts/browser/` (resolve/launch/stop Chrome, MCP wrappers),
`.mcp.json` (project MCP servers `playwright` and `chrome-devtools`), and
`.claude/hooks/session-start.sh`, which installs everything and exports `CHROME_PATH` at the
start of each web session.

## Runtime dependencies

The skills call helper scripts that need tools installed in the session. See each
`SKILL.md` for details. Common ones:

- Python: `python-docx`, `openpyxl`, `python-pptx`, `pypdf`, `pdfplumber`, `reportlab`, `pytesseract`, `pdf2image`
- Node: `docx`, `pptxgenjs`
- System: LibreOffice (`soffice`), `pdftotext`/`qpdf` (poppler), `tesseract`
- Google skills' scripts: `curl`, `jq`, `base64` (coreutils)
- Browser skills: Node 20+, `npm install` at the repo root, a Chrome/Chromium binary
  (Playwright's cache or `CHROME_PATH`), Python `playwright` for `webapp-testing`

## Updating

Re-clone the source repos listed above and copy the skill directories over these. For
`google-drive-api`, re-apply the "Connector tools" section at the end of `SKILL.md`.
