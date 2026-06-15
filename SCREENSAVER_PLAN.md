# Plan: Earthbound Battle Backgrounds → macOS Screensaver (`.saver`)

> Goal: Turn this JS Canvas app into a native macOS screensaver bundle (`.saver`)
> that renders the battle backgrounds and, on a user-configurable timer, randomly
> picks a new combination of layers/effects every X seconds. Configuration UI shows
> up when you click **Options…** for the screensaver in System Settings.

---

## TL;DR of the strategy

The app is **pure client-side JavaScript** rendering to a 2D `<canvas>`, with all the
SNES ROM data bundled in (`data/truncated_backgrounds.dat`). The animation runs itself
via `requestAnimationFrame`. There is already random-layer and "endless random" logic
in [public/assets/form.js](public/assets/form.js) we can reuse.

The cheapest path is **not** to rewrite the rendering engine in Swift. It's to wrap the
existing JS in a tiny native screensaver bundle that hosts a `WKWebView` (an embedded
browser view) loading a stripped-down local copy of the app. A native `Timer` ticks every
X seconds and tells the page to randomize.

**BUT** there is one big risk that decides whether this approach is even viable, so the
plan starts with a throwaway spike to prove it before we build anything real.

---

## ⚠️ The one risk that drives everything: Milestone 0 (go / no-go spike)

On modern macOS (you're on Darwin 25.5 ≈ macOS 26), screensavers run inside a heavily
**sandboxed `legacyScreenSaver` process**. `WKWebView` runs its actual web content in
separate helper (XPC) processes, and those don't always spawn under the screensaver
sandbox — the common failure is a **blank/white screen** with no error. This is the
single tightest constraint in the project. Everything else (config sheet, timer,
packaging) is standard and only matters if rendering works at all.

So before writing real code, do a ~30-minute throwaway spike:

1. Make a trivial `ScreenSaverView` subclass with **no web content** — just fill the
   view with a solid color or draw a moving rectangle. Confirms a bare `.saver` even
   installs and runs on your macOS version.
2. Add a `WKWebView` (created in `init(frame:isPreview:)`, **not** in `animateOneFrame`)
   and `loadFileURL(...)` a local HTML file containing a simple animated colored canvas.
   - Set `webView.isInspectable = true`.
   - Implement the `WKNavigationDelegate` `didFail` / `didFailProvisionalNavigation`
     callbacks and `NSLog` from them, so a blank screen tells you _why_ instead of
     failing silently.
3. Test it **two** ways, because the System Settings preview pane caches aggressively and
   lies:
   - In **System Settings → Screen Saver** preview, and
   - By running the real engine directly:
     `/System/Library/CoreServices/ScreenSaverEngine.app`

**Decision gate:**

- ✅ **Spike renders the animated canvas** → proceed with the WKWebView wrapper plan
  below (Milestones 1–6). This is the good case and most of the rest is routine.
- ❌ **Spike is blank** after trying the known workarounds (see Appendix A) → the
  fallback is a **native Swift/Metal port of the distortion engine**, which is a
  genuinely larger, different project. **Stop and bring this back as a decision** —
  don't silently pivot.

---

## Architecture (assuming the spike passes)

```
┌─────────────────────────────────────────────┐
│  EarthboundBBG.saver  (Cocoa bundle)         │
│                                              │
│  ┌────────────────────────────────────────┐ │
│  │ EBBGScreenSaverView : ScreenSaverView  │ │   Swift/Obj-C
│  │  - hosts a WKWebView (fills the view)  │ │
│  │  - Timer → evaluateJavaScript(...)     │ │
│  │  - hasConfigureSheet / configureSheet  │ │
│  │  - reads interval from ScreenSaverDefaults
│  └────────────────────────────────────────┘ │
│                    │ loads                    │
│  ┌────────────────────────────────────────┐ │
│  │ Resources/web/  (vite build output)    │ │   JS (reused)
│  │  - screensaver.html (minimal, no forms)│ │
│  │  - bundled engine + ROM data           │ │
│  │  - exposes window.EBBG.randomize()     │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

Two halves: a thin **native shell** (timer + config + window plumbing) and the **reused
JS renderer**, talking through one tiny bridge call (`window.EBBG.randomize()`).

---

## Milestone 1 — Build a stripped, self-contained web bundle

The current `index.html` is a full website (forms, GitHub buttons, history adapter,
Google Analytics, external CDN CSS). A screensaver needs none of that, and a sandboxed
screensaver phoning out to `google-analytics.com` / `unpkg.com` is both likely blocked
and wrong. Strip to the essentials.

1. Create `screensaver.html`: just a fullscreen `<canvas>` and a `<script type="module">`
   that boots the engine — no forms, no analytics, no external `<link>`/`<script>` CDNs.
2. Create a small entry module (e.g. `src/screensaver.js`) that:
   - Imports `Rom`, `Engine`, `BackgroundLayer` (same as [src/index.js](src/index.js)).
   - Boots with a random layer pair.
   - Exposes a global the native side can call:
     ```js
     window.EBBG = {
       randomize() {
         const l1 = Math.floor(Math.random() * 327);
         const l2 = Math.floor(Math.random() * 327);
         // rebuild layers + restart engine with new layers/aspect/frameskip
       },
     };
     ```
     (Reuse the random logic from [public/assets/form.js](public/assets/form.js):
     `setRandomLayer` and the engine re-init pattern in `setupDropdownPushStates`.)
3. **Pixel scaling:** the canvas is 256×224. To fill a Retina display without looking
   like mush, scale up with CSS `image-rendering: pixelated` (the engine already sets
   `imageSmoothingEnabled = false`, which is correct). Set body background black and
   center/letterbox the canvas.
4. Configure Vite to build this as a **self-contained** bundle (relative asset paths,
   single output dir, ROM data inlined as it already is via the `?uint8array&base64`
   import). Output to something like `dist-saver/`.
5. **Verify in a plain browser first** (`open dist-saver/screensaver.html` via a local
   file server) that it animates and that calling `window.EBBG.randomize()` in the
   console swaps the background. Debugging here is 10× easier than inside a screensaver.

**Outcome:** a `dist-saver/` folder that animates standalone and exposes one randomize
function.

---

## Milestone 2 — Create the Xcode screensaver project

In Xcode:

1. **File → New → Project**.
2. Choose the **macOS** tab, then the **Screen Saver** template.
   - Note: the exact category/location of this template moves between Xcode versions —
     look under the macOS templates; don't trust a hardcoded menu path. If you can't find
     it, search "Screen Saver" in the template chooser.
3. Name it e.g. `EarthboundBBG`. Pick Swift as the language.
   - This generates a `ScreenSaverView` subclass and an `Info.plist` pre-wired with
     `NSPrincipalClass` pointing at your view.
4. Build once (⌘B) to confirm it compiles, producing a `.saver` bundle in
   `~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/`.

---

## Milestone 3 — Host the WKWebView and load the bundle

In the generated `ScreenSaverView` subclass:

1. Add the web bundle to the Xcode project: drag `dist-saver/` into the project, choose
   **"Create folder references"** (blue folder, preserves structure) and add it to the
   target's **Copy Bundle Resources** build phase. It lands in `…/Contents/Resources/`.
2. In `init(frame:isPreview:)`:
   - Create the `WKWebView`, add it as a subview pinned to fill (`autoresizingMask` or
     Auto Layout).
   - Resolve the local HTML:
     ```swift
     let webDir = Bundle(for: type(of: self)).url(forResource: "web", withExtension: nil)!
     let indexURL = webDir.appendingPathComponent("screensaver.html")
     webView.loadFileURL(indexURL, allowingReadAccessTo: webDir)
     ```
   - Set `webView.isInspectable = true` (keep during dev), and a `WKNavigationDelegate`
     that `NSLog`s failures.
3. Make the view's background black so any letterboxing looks intentional.

**Test the same two ways** as the spike (System Settings preview _and_
`ScreenSaverEngine.app`).

---

## Milestone 4 — The randomize timer

1. Add a property for the interval (seconds), default e.g. 10.
2. In `startAnimation()`:
   - Call `super.startAnimation()`.
   - **Re-read** the interval from defaults here (so a changed setting takes effect on
     the next run without reinstalling).
   - Schedule a `Timer.scheduledTimer(withTimeInterval: interval, repeats: true)` whose
     handler calls:
     ```swift
     webView.evaluateJavaScript("window.EBBG && window.EBBG.randomize()")
     ```
3. In `stopAnimation()`: invalidate the timer and call `super.stopAnimation()`.

Keeping the interval in Swift (not baked into a query param) means the config sheet can
change it cleanly.

> Note: we do **not** need to drive frames from `animateOneFrame()` — the JS engine
> animates itself via `requestAnimationFrame` inside the WebView. The native timer is
> only for the every-X-seconds _randomization_.

---

## Milestone 5 — The configuration (Options…) sheet

This is the "edit the screensaver in System Settings" UI.

1. Override:
   ```swift
   override var hasConfigureSheet: Bool { true }
   override var configureSheet: NSWindow? { /* return the options window */ }
   ```
2. Build a small window/panel (programmatically or a `.xib`) with:
   - A field/stepper/slider for **"Pick a new background every \_\_\_ seconds"**.
   - (Optional, nice-to-have) toggles for aspect ratio / frameskip randomization.
   - **OK** and **Cancel** buttons; OK closes the sheet with
     `NSApp.endSheet(window)` / modern equivalent.
3. Persist with `ScreenSaverDefaults`:
   ```swift
   let defaults = ScreenSaverDefaults(forModuleWithName: Bundle(for: type(of: self)).bundleIdentifier!)!
   defaults.set(interval, forKey: "randomizeInterval")
   defaults.synchronize()
   ```
   Read the same key on init / `startAnimation`. Provide a sensible default if unset.
4. **Verify the live instance picks up a changed interval** — change it in Options, close,
   re-open the preview, confirm the cadence changed.

---

## Milestone 6 — Install, sign, and ship

1. **Personal install (default assumption):** build, then double-click the `.saver` (or
   right-click → Open) to install into `~/Library/Screen Savers/`. Unsigned is fine for
   your own machine — you'll get a Gatekeeper prompt you can bypass (right-click → Open,
   or allow in System Settings → Privacy & Security).
2. **Only if you intend to distribute it to others:** you'll need a **Developer ID**
   signature + **notarization**. That's meaningfully more setup (Apple Developer account,
   `codesign`, `notarytool`, stapling). **Tell me which you want** — we shouldn't
   over-engineer for distribution if this is just for you.

---

## Cross-cutting: iterating on a screensaver is genuinely painful

The OS caches the installed `.saver` aggressively, so a rebuild frequently won't show up.
Budget for this so it doesn't read as "something's broken." Typical reset loop between
builds:

1. Quit System Settings.
2. `killall legacyScreenSaver` (and `killall ScreenSaverEngine` if running).
3. Remove the old copy from `~/Library/Screen Savers/`.
4. Copy the freshly built `.saver` in.
5. Re-open System Settings → Screen Saver.

A small shell script to do steps 2–4 will save a lot of frustration. Prefer testing via
`ScreenSaverEngine.app` during development — it's faster and more honest than the preview
pane.

---

## Appendix A — WKWebView-in-screensaver blank-screen workarounds (try during the spike)

If the spike shows blank, before declaring the wrapper dead, try:

- Creating the WKWebView in `init`, never in `animateOneFrame`.
- Using `loadFileURL(_, allowingReadAccessTo:)` with the **directory** (not the file) for
  read access.
- Loading via a tiny embedded HTTP server / `loadHTMLString` instead of `file://` (some
  sandbox configs treat `file://` differently).
- Adding a `WKNavigationDelegate` and logging failures to find the real cause.
- Checking Console.app filtered to `legacyScreenSaver` / `WebContent` for sandbox-denial
  messages.
- Confirming the bare (non-web) `ScreenSaverView` from spike step 1 works — isolates
  "screensavers broken on this OS" from "WKWebView blocked."

## Appendix B — Fallback if WKWebView is a dead end

Native Swift port: reimplement the ROM parsing (`src/rom/*.js`) and the distortion math
(the `Offset(y,t) = A·sin(F·y + S·t)` effects in
[src/rom/distortion_effect.js](src/rom/distortion_effect.js) /
[src/rom/distorter.js](src/rom/distorter.js)) in Swift, rendering per-frame in
`animateOneFrame()` via Core Graphics or Metal. This reuses the _algorithm_ and the
_data file_ but rewrites the engine. Larger effort — a separate decision, not part of
this plan's happy path.

---

## Open questions for you

1. **Personal use or distribution?** (Decides whether we do code signing + notarization.)
2. Beyond the **interval**, do you want the Options sheet to also randomize **aspect
   ratio** and **frameskip**, or keep those fixed/sensible-default?
3. Any preference on **default interval** and bounds (e.g. 5–120 seconds)?
