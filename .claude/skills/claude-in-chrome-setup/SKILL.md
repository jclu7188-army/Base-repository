---
name: claude-in-chrome-setup
description: Install, connect, and troubleshoot the Claude in Chrome browser extension with Claude Code (the `--chrome` flag and `/chrome` command), and decide which browser path fits the session — the user's own Chrome via the extension, the desktop app's built-in browser, or headless Chromium in this repository. Use it when the user asks to "install the Claude Chrome extension", "connect Chrome", "use my browser", "claude --chrome", sees "Browser extension is not connected", or asks whether Claude can use their logged-in Chrome from a cloud session. Once the extension is connected, the chrome-browser skill covers how to drive it.
---

## Which browser is available where

| Session runs in | User's Chrome (Claude in Chrome) | Desktop app built-in browser | Headless Chromium in this repo |
|-----------------|----------------------------------|------------------------------|--------------------------------|
| Claude Code CLI or VS Code on the user's machine | Yes — `claude --chrome`, tools `mcp__claude-in-chrome__*` | No | Yes (`npm run browser:check`) |
| Cowork in the desktop app | Yes, when the extension is installed and Chrome is running | Yes, tools `mcp__Claude_Browser__*` | Yes |
| Cloud session (claude.ai/code, mobile, this container) | Only if the session is linked to the user's computer and the extension is connected there; otherwise **no** | Only when linked to a computer running the desktop app (`mcp__remote-devices__Claude_Browser__*`) | **Yes** — the default here |

Rule: check the tool list. `mcp__claude-in-chrome__*` (or `enable__mcp__claude-in-chrome`)
present → read the `chrome-browser` skill and use it. `mcp__Claude_Browser__*` /
`mcp__remote-devices__Claude_Browser__*` present → `built-in-browser` skill. Neither → this
container has no access to the user's browser; use the `playwright` or `chrome-devtools` skill
with the headless Chromium installed in this repository, and say so plainly. The extension
cannot be "installed into" a cloud container: it lives in the user's Chrome on their computer.

## Installing the extension (on the user's machine)

Prerequisites:

- Google Chrome, Microsoft Edge, or another Chromium browser (Brave, Arc, Vivaldi, Opera).
  Not supported inside WSL.
- Claude in Chrome extension **1.0.36 or later** from the Chrome Web Store:
  https://chromewebstore.google.com/detail/claude/fcoeoabgfenejglbffodgkkbkcdhcgfn
- Claude Code installed and signed in with `/login` on a direct Anthropic plan (Pro, Max, Team,
  Enterprise). API-key or `claude setup-token` sessions keep Chrome integration off. Not
  available through Bedrock, Google Cloud Agent Platform, or Microsoft Foundry.

Steps:

1. Install the extension from the store link above and keep Chrome running.
2. Start Claude Code with `claude --chrome`. The first run shows a one-time dialog explaining
   site permissions; press Enter. Claude Code writes a native-messaging host manifest so Chrome
   can reach it; if the extension is "Not detected" on the first try, restart Chrome.
3. Ask for a browser task. Approve the "Claude in Chrome wants to …" prompt (optionally allow
   all actions on that site for the session). Claude opens its own tabs in a tab group.
4. If Claude Code needs the browser and finds no extension, it offers **Install extension**
   (guided setup, then "Continue with browser tools"), **Not now**, or **Don't ask again**.

`/chrome` at any time: shows Status (Enabled / Disabled) and Extension (Installed / Not
detected), **Enabled by default** (no more `--chrome`; costs context because the tools are
always loaded), **Reconnect extension**, **Select browser…** when more than one browser is
connected. In VS Code the integration is on whenever the extension is installed.

What it can do once connected: use the user's existing sign-ins (Gmail, Google Docs, Notion,
internal apps) without API connectors, read console messages and DOM, fill forms, upload local
files (≤10 MB per upload, respects `Read` permission rules), record GIFs, save screenshots
to disk. It pauses at login pages and CAPTCHAs for the user. Site permissions are managed in
the extension's settings.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Extension "Not detected" in `/chrome` | Not installed, disabled, or Chrome not running | Check `chrome://extensions`, start Chrome, `/chrome` → Reconnect extension, restart both |
| "Browser extension is not connected" | Native messaging host can't reach the extension, or an org IP allowlist blocks `bridge.claudeusercontent.com` | Restart Chrome and Claude Code, `/chrome` → Reconnect; check network allowlists |
| "Receiving end does not exist" | Extension service worker went idle after a long session | `/chrome` → Reconnect extension |
| "No tab available" | Action fired before a tab existed | Ask Claude to create a new tab and retry |
| Browser stops responding | A JavaScript `alert`/`confirm`/`prompt` is open | Dismiss it manually, then continue |
| Windows `EADDRINUSE` | Another Claude Code session holds the named pipe | Close other sessions, restart |
| `--chrome` ignored | Signed in with API key / setup-token | `/login` with a claude.ai account |

Native messaging host manifest locations (`com.anthropic.claude_code_browser_extension.json`):

- macOS Chrome: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`
- Linux Chrome: `~/.config/google-chrome/NativeMessagingHosts/`
- Linux Edge: `~/.config/microsoft-edge/NativeMessagingHosts/`
- Windows: registry `HKCU\Software\Google\Chrome\NativeMessagingHosts\` (Edge: `…\Microsoft\Edge\…`)
- Other Chromium browsers: their own profile directory, e.g. `BraveSoftware/Brave-Browser/`.

## Related tooling in this repository

- Headless Chromium, Playwright, and two MCP servers (`playwright`, `chrome-devtools`) are
  installed and verified by the SessionStart hook; see the `playwright` and `chrome-devtools`
  skills and `scripts/browser/`.
- Microsoft's Playwright MCP can also attach to a *local* Chrome/Edge tab through its own
  "Playwright Extension" (`--extension` flag) — an alternative to Claude in Chrome for
  developers running Claude Code locally who want their logged-in browser without the Anthropic
  extension. It is unrelated to the Claude extension and needs that separate extension installed.
- Computer use (desktop control through the Claude desktop app) is a further fallback for
  native apps; see the `computer-use` skill.

Source for the facts above: https://code.claude.com/docs/en/chrome (checked 2026-09-27).
