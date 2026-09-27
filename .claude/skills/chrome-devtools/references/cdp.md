# Chrome DevTools Protocol quick reference

Full schema for the running browser: `curl -s http://127.0.0.1:9222/json/protocol`. Online:
https://chromedevtools.github.io/devtools-protocol/ (tot / 1-3 / stable tabs).

## Transport

- Browser-level WebSocket: `webSocketDebuggerUrl` from `/json/version`. Page-level: from
  `/json/list`. Messages are JSON `{id, method, params}`; replies carry the same `id`; events
  have `method` + `params` and no `id`.
- Sessions: on the browser socket, `Target.attachToTarget({targetId, flatten: true})` returns a
  `sessionId`; include `"sessionId"` in subsequent messages to talk to that target.
- Playwright: `context.newCDPSession(page)` or `browser.newBrowserCDPSession()`;
  Puppeteer: `page.createCDPSession()`.

## Domains you will actually use

| Domain | Methods / events |
|--------|------------------|
| Target | `getTargets`, `createTarget({url})`, `closeTarget`, `attachToTarget`, `setDiscoverTargets`; events `targetCreated`, `targetDestroyed` |
| Page | `navigate({url})`, `reload`, `captureScreenshot({format, clip, captureBeyondViewport})`, `printToPDF({printBackground, paperWidth, paperHeight})`, `getLayoutMetrics`, `setLifecycleEventsEnabled`; events `loadEventFired`, `frameNavigated`, `lifecycleEvent`, `javascriptDialogOpening` → `handleJavaScriptDialog({accept})` |
| Runtime | `evaluate({expression, returnByValue, awaitPromise})`, `callFunctionOn`, `getProperties`; events `consoleAPICalled`, `exceptionThrown` (after `enable`) |
| Log | `enable`; event `entryAdded` (browser-level warnings, network errors) |
| DOM | `getDocument({depth: -1})`, `querySelector`, `querySelectorAll`, `getOuterHTML`, `getBoxModel`, `focus`, `setFileInputFiles`, `getAttributes` |
| Input | `dispatchMouseEvent({type: mousePressed|mouseReleased|mouseMoved, x, y, button, clickCount})`, `dispatchKeyEvent({type: keyDown|keyUp|char, text, key})`, `insertText`, `synthesizeScrollGesture` |
| Network | `enable`, `setExtraHTTPHeaders`, `setUserAgentOverride`, `setBlockedURLs`, `setCacheDisabled`, `emulateNetworkConditions({offline, latency, downloadThroughput, uploadThroughput})`, `getResponseBody({requestId})`, `getCookies`, `setCookie`, `clearBrowserCookies`; events `requestWillBeSent`, `responseReceived`, `loadingFinished`, `loadingFailed` |
| Fetch | `enable({patterns})` then `requestPaused` events → `continueRequest`, `fulfillRequest({responseCode, body})`, `failRequest` — request interception and mocking |
| Emulation | `setDeviceMetricsOverride({width, height, deviceScaleFactor, mobile})`, `setUserAgentOverride`, `setGeolocationOverride`, `setTimezoneOverride`, `setEmulatedMedia({media, features})`, `setCPUThrottlingRate({rate})`, `setLocaleOverride` |
| Performance | `enable`, `getMetrics` (Timestamp, Documents, JSHeapUsedSize, LayoutCount, ScriptDuration, TaskDuration …) |
| Tracing | `start({categories, transferMode: 'ReturnAsStream', options})`, `end`; events `dataCollected`, `tracingComplete({stream})` → `IO.read({handle})` until `eof` |
| Profiler | `enable`, `start`, `stop` (CPU profile), `startPreciseCoverage`, `takePreciseCoverage` |
| HeapProfiler | `takeHeapSnapshot({reportProgress})` → `addHeapSnapshotChunk` events; `collectGarbage` |
| CSS | `enable`, `getMatchedStylesForNode({nodeId})`, `getComputedStyleForNode`, `setStyleTexts` |
| Accessibility | `getFullAXTree`, `getPartialAXTree({nodeId})` — what snapshot tools are built on |
| Security | `setIgnoreCertificateErrors({ignore: true})` |
| Browser | `getVersion`, `getWindowForTarget`, `setWindowBounds`, `grantPermissions({permissions})`, `setDownloadBehavior({behavior: 'allow', downloadPath})` |
| Storage | `clearDataForOrigin`, `getCookies`, `setCookies`, `clearCookies` |

## Useful Chrome flags (pass after `--` to `chrome-launch.sh`)

`--headless=new`, `--window-size=W,H`, `--user-data-dir=DIR`, `--incognito`,
`--disable-gpu`, `--no-sandbox` (root), `--lang=xx`, `--proxy-server=host:port`,
`--ignore-certificate-errors`, `--host-resolver-rules="MAP example.com 127.0.0.1"`,
`--auto-open-devtools-for-tabs`, `--enable-logging=stderr --v=1`, `--disable-extensions`,
`--load-extension=/path/to/unpacked` (headless=new supports extensions),
`--remote-allow-origins=*` (needed for WebSocket clients that send an `Origin` header).

## Tracing categories for a performance trace

```
-*,devtools.timeline,disabled-by-default-devtools.timeline,disabled-by-default-devtools.timeline.frame,
toplevel,blink.console,blink.user_timing,latencyInfo,disabled-by-default-devtools.screenshot,
disabled-by-default-v8.cpu_profiler,loading,v8.execute
```

Open the resulting JSON in DevTools → Performance → Load profile.
