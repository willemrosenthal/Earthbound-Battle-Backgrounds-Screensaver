# Earthbound Battle Backgrounds — macOS Screensaver

A native macOS screensaver (`.saver`) that renders the hypnotic, distorting battle
backgrounds from the SNES RPG **EarthBound / Mother 2**, picking a new random
combination of layers and effects on a timer.

This is a **fork** of Garen Torikian's
[Earthbound-Battle-Backgrounds-JS](https://github.com/gjtorikian/Earthbound-Battle-Backgrounds-JS),
a client-side JavaScript implementation. The rendering engine (ROM data parsing,
tile/palette decoding, and the sine-based distortion effects) was ported from that
project's JavaScript to **native Swift**, and wrapped in a macOS `ScreenSaverView`
so it runs as a real system screensaver with no browser, no JavaScript, and no
network access. The original JS web app is still present in this repo (`src/`,
`index.html`) for reference and as the ground-truth the port was validated against.

## Features

- Native, self-contained `.saver` — pure Swift + the bundled ROM data file.
- Randomly switches to a new background combination every _N_ seconds.
- **Options…** sheet (in System Settings) to configure the change interval and the
  animation speed (frameskip).
- Fills the display; universal build runs on **Apple Silicon and Intel**, macOS 12+.

## Install

**From a release (easiest):** download `EarthboundBattle-Screensaver.zip` from the
[Releases page](https://github.com/willemrosenthal/Earthbound-Battle-Backgrounds-Screensaver/releases),
unzip, right-click **Install.command** → **Open**, then choose **EarthboundBattle**
in **System Settings → Screen Saver**. (It's a free, un-notarized fan project, hence
the one-time "unidentified developer" prompt — it's safe to open.)

**From source:** open `EarthboundBattle/EarthboundBattle.xcodeproj` in Xcode and
build, or run the helper script:

```bash
./EarthboundBattle/install-saver.sh   # build, install to ~/Library/Screen Savers, ad-hoc sign
```

See [RELEASE.md](RELEASE.md) for building shareable packages and cutting GitHub
releases.

## How it works

Every battle background is composed of two layers, each with 327 possible styles
(including "blank"/zero). The layer styles can be interchanged, so there are
C(n,r) = 52,650 possible combinations — though the SNES could only properly render
3,176 of them, and only 225 are ever used in the game.

The data for each style is bundled within the SNES cartridge; tiles are constructed
from various memory addresses in the game data. The distortion effect is computed
per scanline as:

```
Offset(y, t) = A · sin(F·y + S·t)
```

where _y_ is the vertical coordinate being transformed, _t_ is elapsed time, _A_ is
the amplitude, _F_ is the frequency, and _S_ is the speed of the transformation.
There are three distortion modes that use this offset:

- **Horizontal** — each line is shifted left/right by the offset.
- **Horizontal interlaced** — every other line is shifted in the opposite direction.
- **Vertical** — each line is shifted up/down (sampled from a different source row).

Different backgrounds use different distortion effects and palette-cycling
animations.

## Repository layout

- `EarthboundBattle/` — the native macOS screensaver (Xcode project + Swift port).
- `src/`, `index.html` — the original JavaScript web app (reference implementation).
- `SCREENSAVER_PLAN.md` — design/porting notes for the native screensaver.
- `RELEASE.md` — how to build packages and publish releases.

## Credits & related projects

- **Original JavaScript implementation:**
  [gjtorikian/Earthbound-Battle-Backgrounds-JS](https://github.com/gjtorikian/Earthbound-Battle-Backgrounds-JS)
  by Garen Torikian — this screensaver is a port of that engine.
- **Android live wallpaper:**
  [gjtorikian/Earthbound-Battle-Backgrounds](https://github.com/gjtorikian/Earthbound-Battle-Backgrounds).
- The math behind the distortion effects was originally worked out by **Mr.
  Accident** of forum.starmen.net (whose work, fittingly, was itself a C# Windows
  screensaver). In 2016, [@kdex](https://github.com/kdex) rewrote much of the JS into
  clean ES2016, which the Swift port follows closely.
- Everyone who worked on PK Hack and reverse-engineered the EarthBound ROM format.

## License

MIT. This app is in no way endorsed by or affiliated with Nintendo, Ape, HAL
Laboratory, Shigesato Itoi, etc. Please don't sue anybody.
