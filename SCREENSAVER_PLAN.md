# Plan: Earthbound Battle Backgrounds → **fully native** macOS Screensaver (`.saver`)

> Goal: A 100% native Swift screensaver bundle (`.saver`). No web view, no
> JavaScript, no embedded browser, no network. We port the rendering engine
> directly to Swift and draw with Core Graphics. On a user-configurable timer it
> randomly picks a new background combination every X seconds. The interval is
> editable via **Options…** in System Settings → Screen Saver.

---

## Why native (and why this is actually the _easy_ version)

The original WKWebView approach carried a real risk of a blank screen inside the
sandboxed `legacyScreenSaver` process. Going native removes that risk entirely.

The good news: **the rendering engine has no web dependency.** It's pure,
deterministic math over a single 121 KB binary blob (`truncated_backgrounds.dat`):

- It reads bytes from that blob, decompresses some chunks, builds 8×8 tiles,
  applies a 16-color palette, and produces a **256×224 RGBA pixel buffer**.
- The animation is a per-scanline sine distortion: `offset(y,t) = A·sin(F·y + S·t)`.
- No GPU shaders. No threads. ~57k pixels × 2 layers at 30 fps — trivial for a CPU.

So we (1) translate ~10 small JS files to Swift, (2) draw the resulting pixel
buffer into the screensaver view scaled up with nearest-neighbor (crisp pixels),
(3) add a timer + an options sheet. That's the whole project.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  EarthboundBBG.saver  (Cocoa bundle, 100% Swift)               │
│                                                                │
│  EBBGScreenSaverView : ScreenSaverView                         │
│    • owns two BackgroundLayer instances (layer1 + layer2)      │
│    • animateOneFrame(): advance tick → render → setNeedsDisplay│
│    • draw(_:): blit RGBA buffer → CGImage → fill bounds        │
│                (interpolationQuality = .none → crisp pixels)   │
│    • Timer every X s → randomize() picks new layer pair        │
│    • hasConfigureSheet / configureSheet → interval slider      │
│    • interval persisted via ScreenSaverDefaults                │
│                                                                │
│  Engine (ported from JS, no UI):                               │
│    Rom ── Block ── decompress()                                │
│      ├─ BattleBackground   (17-byte struct parse)              │
│      ├─ BackgroundGraphics ─ RomGraphics (tiles, draw)         │
│      ├─ BackgroundPalette  (15-bit SNES color → RGBA)          │
│      ├─ PaletteCycle       (palette animation)                 │
│      ├─ DistortionEffect   (17-byte effect params)             │
│      └─ Distorter          (sine scanline offset)              │
│                                                                │
│  Resources/                                                    │
│    └─ truncated_backgrounds.dat   (121 KB, bundled as-is)      │
└──────────────────────────────────────────────────────────────┘
```

---

## The port map (JS → Swift)

Each current JS file maps to one Swift type. The translation is mechanical; the
only thing to be careful about is **integer width / overflow semantics** (see the
"Gotchas" section). Order them so each compiles before the next.

| JS file (`src/rom/…`)    | Swift type           | What it does                                                                                                                |
| ------------------------ | -------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `rom.js` (free fns)      | `Rom` + helpers      | Holds the `[UInt8]` data blob; `decompress`, `getCompressedSize`, `snesToHex`, `REVERSED_BYTES`; builds all objects on init |
| `block.js`               | `Block`              | Cursor into the blob: `readInt16` (reads **one byte** — see gotcha), `readInt32`, `readDoubleShort`, `decompress`           |
| `battle_background.js`   | `BattleBackground`   | Parses a 17-byte entry (graphics idx, palette idx, bpp, cycle params, effect bytes)                                         |
| `background_palette.js`  | `BackgroundPalette`  | 15-bit SNES BGR → 32-bit RGBA colors                                                                                        |
| `palette_cycle.js`       | `PaletteCycle`       | Animates palette indices over time (types 1/2/3)                                                                            |
| `rom_graphics.js`        | `RomGraphics`        | Decodes 2bpp/4bpp tiles, draws 32×32 tile grid into the 256×256 buffer                                                      |
| `background_graphics.js` | `BackgroundGraphics` | Loads + decompresses graphics & arrangement, calls `RomGraphics.draw`                                                       |
| `distortion_effect.js`   | `DistortionEffect`   | Parses 17-byte effect params (amplitude, frequency, compression, speed, accelerations)                                      |
| `distorter.js`           | `Distorter`          | The visual effect: sine offset per scanline; horizontal / interlaced / vertical modes                                       |
| `background_layer.js`    | `BackgroundLayer`    | Ties graphics+palette+distorter; `overlayFrame()` renders one layer into the shared buffer                                  |
| `engine.js`              | folded into the view | Composites the two layers (alpha blend) and advances `tick` by `frameSkip`                                                  |

Files we **drop** (web-only): `index.js`, everything in `public/assets/` (forms,
GIF maker, analytics, history), `index.html`, Vite config. The suggested-layers
list in `form.js` is optional flavor we can port later if wanted.

---

## Rendering: how the pixels reach the screen

1. The engine fills a buffer of `256 × 224` pixels. JS stores it as `Int16Array`
   (RGBA, stride 1024). In Swift use a `[UInt8]` (or `UnsafeMutableBufferPointer`)
   of `256*224*4`, clamping each channel to 0…255 on write.
2. Each frame, wrap that buffer in a `CGImage`:
   - `CGColorSpaceCreateDeviceRGB()`, `CGImageAlphaInfo.premultipliedLast` (RGBA),
     `bitsPerComponent: 8`, `bytesPerRow: 256*4`, via a `CGDataProvider`.
3. In `draw(_ rect:)`:
   - `context.interpolationQuality = .none` ← **critical** for crisp retro pixels.
   - Draw the CGImage stretched to fill the view bounds (optionally letterboxed to
     keep the 8:7 / chosen aspect ratio with black bars).

This is plenty fast on the CPU; no Metal required. (If we ever wanted it, a Metal
texture upload is a drop-in upgrade, but it's unnecessary here.)

---

## Milestones

### Milestone 1 — Xcode project + "hello, moving rectangle"

1. **File → New → Project**, macOS tab, **Screen Saver** template (search "Screen
   Saver" in the chooser if the category isn't obvious — its location moves between
   Xcode versions). Language: **Swift**. Name it `EarthboundBBG`.
2. This generates a `ScreenSaverView` subclass + an `Info.plist` with
   `NSPrincipalClass` already wired to your view.
3. Replace the generated `draw`/`animateOneFrame` with a moving colored rectangle.
   Build (⌘B), then **install and verify** (see "Install & test loop" below).
   - This proves the toolchain + install path before any porting work.

### Milestone 2 — Bundle the data + load it

1. Drag `data/truncated_backgrounds.dat` into the project; add to the target's
   **Copy Bundle Resources**.
2. Load at startup:
   ```swift
   let url = Bundle(for: type(of: self)).url(forResource: "truncated_backgrounds", withExtension: "dat")!
   let bytes = [UInt8](try! Data(contentsOf: url))
   ```
3. Verify the byte count is 121,056 with an `NSLog`. (Cheap sanity check that the
   resource is actually in the bundle — a common screensaver footgun.)

### Milestone 3 — Port the engine (the bulk of the work)

Port the files in the order in the table above. Strategy to keep it sane:

1. Port `Rom` + `Block` + `decompress` first; that's the foundation everything
   reads through.
2. Port `BattleBackground`, `BackgroundPalette`, `RomGraphics`,
   `BackgroundGraphics`, `PaletteCycle` — enough to render **one static frame** of
   a single layer (skip distortion at first).
3. **Checkpoint:** render layer entry `1` (or any known-good index) as a static
   image. Compare it visually against the live web app at
   `?layer1=<n>&layer2=0` to confirm the tile/palette decode is byte-correct.
   This is the single most important checkpoint — if static frames match, the
   hard part is done.
4. Port `DistortionEffect` + `Distorter` to add the animated wobble.
5. Port `BackgroundLayer.overlayFrame` and the two-layer alpha composite from
   `engine.js`. Now both layers animate and blend.

### Milestone 4 — Animation loop

1. Set `animationTimeInterval` for ~30 fps in `init`.
2. In `animateOneFrame()`: advance `tick += frameSkip`, run both layers'
   `overlayFrame` into the buffer, then `setNeedsDisplay(bounds)` (or draw
   directly). Keep allocations out of the hot loop — reuse the buffer.

### Milestone 5 — The randomize timer

1. Add `randomizeInterval` (seconds), default 10.
2. In `startAnimation()`: call `super`, **re-read the interval from defaults**, and
   schedule a repeating `Timer` whose handler calls `randomize()`.
3. `randomize()`: pick `layer1 = Int.random(in: 0..<327)`, `layer2 =
Int.random(in: 0..<327)` (mirror the web app's range), rebuild the two
   `BackgroundLayer`s, reset alpha (1.0 if layer2 == 0, else 0.5 each — matches
   `index.js`).
4. In `stopAnimation()`: invalidate the timer, call `super`.

### Milestone 6 — Options… configuration sheet

1. Override `hasConfigureSheet { true }` and `configureSheet`.
2. Small window: a slider/stepper + label "Pick a new background every \_\_\_
   seconds" (bounds e.g. 3–120), plus OK/Cancel.
3. Persist via:
   ```swift
   let defaults = ScreenSaverDefaults(forModuleWithName: Bundle(for: type(of: self)).bundleIdentifier!)!
   defaults.set(interval, forKey: "randomizeInterval"); defaults.synchronize()
   ```
   Read the same key on init/`startAnimation`, with a default when unset.
4. (Optional) toggles to also randomize aspect ratio / frameskip, or a fixed-layer
   "favorite" mode. Decide later — not required for v1.

### Milestone 7 — Install / sign / ship

- **Personal use (assumed default):** build, double-click the `.saver` (or
  right-click → Open to clear Gatekeeper) to install into `~/Library/Screen Savers/`.
  Unsigned is fine for your own machine.
- **Distribution to others:** requires Developer ID signing + notarization
  (Apple Developer account, `codesign`, `notarytool`, stapling). More setup — only
  if you actually plan to share it. **Tell me which you want.**

---

## Install & test loop (read this before you start iterating)

macOS caches installed screensavers aggressively; a fresh build often won't show
up until you reset. Expect this — it's not a bug in your code. Between builds:

1. Quit System Settings.
2. `killall legacyScreenSaver` (and `killall ScreenSaverEngine` if running).
3. Remove the old copy from `~/Library/Screen Savers/`.
4. Copy the freshly built `.saver` in.
5. Re-open System Settings → Screen Saver, **and/or** run the real engine directly
   for faster iteration: `/System/Library/CoreServices/ScreenSaverEngine.app`.

A 3-line shell script for steps 2–4 will save real frustration.

---

## Gotchas to respect during the port (where bugs will hide)

- **`Block.readInt16` reads a single byte**, despite the name. The data blob is a
  byte array; `data[pointer++]` returns one `UInt8`. `readInt32` combines 4 bytes
  little-endian; `readDoubleShort` combines 2 bytes into a signed 16-bit value.
  Mirror this exactly — don't "fix" the naming into real 16-bit reads.
- **Signed 16-bit casts matter.** `distortion_effect.js` casts results to `Int16`
  (`asInt16`). Distortion amplitude/frequency/compression can legitimately be
  negative. Use `Int16` where the JS does and let it wrap the same way, then widen
  to `Int`/`Double` for the math.
- **The decompressor is load-bearing and finicky** (`decompress` / 8 command
  types, bit-reversal table). Port it verbatim, byte for byte. Don't refactor it
  on the first pass. A single off-by-one corrupts whole backgrounds.
- **Pixel buffer is `Int16` in JS, additive across layers.** With alpha 0.5+0.5
  the sums stay ≤255, but write through a clamp (`min(255, …)`) to be safe, and
  emit `UInt8` for the CGImage.
- **Stride is 1024** (256 px × 4 bytes) in the source 256-tall buffer; the visible
  output is 224 rows. Keep the letterbox handling from `distorter.js`.
- **SNES color is 15-bit BGR**: `r=(c&31)*8, g=((c>>5)&31)*8, b=((c>>10)&31)*8`.
  Note the channel order — easy to swap R/B by accident.
- **Validate against the web app** at each checkpoint (`?layer1=&layer2=`). It's
  the ground truth; a side-by-side catches decode bugs instantly.

---

## Open questions for you

1. **Personal use or distribution?** (Decides code signing / notarization.)
2. Want me to **write all the ported Swift source files now** so you can drop them
   into the Xcode project, or do you want to go milestone-by-milestone together?
3. Default randomize interval + bounds? (Proposed: default 10s, range 3–120s.)
4. Besides interval, should Options also randomize **aspect ratio** / **frameskip**,
   or keep those at sensible fixed defaults for v1?
