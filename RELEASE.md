# Releasing the EarthboundBattle screensaver

This project ships a native macOS screensaver (`EarthboundBattle/`). Releases are
built and published automatically by GitHub Actions
([.github/workflows/release.yml](.github/workflows/release.yml)): a macOS runner
builds a **universal** (Apple Silicon + Intel), ad-hoc-signed `.saver`, packages it
into `EarthboundBattle-Screensaver.zip` (with a one-click `Install.command` and a
`README.txt`), and attaches it to a GitHub Release.

No Apple Developer account or secrets are required — the build is ad-hoc signed, so
downloaders do a one-time "Open anyway" / right-click-Open step (covered in the
release notes and the bundled README).

## Prerequisites (one-time per release commit)

The workflow runs from the commit the tag points at, so that commit must contain
**both** the workflow file and the `EarthboundBattle/` project. The screensaver work
currently lives on the `screensaver-works` branch.

1. Commit any outstanding changes.
2. Merge the screensaver branch into your release branch (e.g. `main`):
   ```bash
   git checkout main
   git merge screensaver-works
   git push origin main
   ```

## Cut a release

### Option A — push a tag (recommended)

```bash
git checkout main
git tag v1.0.0          # use the version you want
git push origin v1.0.0
```

The workflow runs and, when it finishes, a new Release appears on the repo's
**Releases** page with `EarthboundBattle-Screensaver.zip` attached.

### Option B — run it manually

1. Go to the repo's **Actions** tab on GitHub.
2. Select **Build & Release Screensaver** → **Run workflow**.
3. Enter a tag (e.g. `v1.0.0`) and run. The tag is created at the current branch tip.

## Versioning

Use `vMAJOR.MINOR.PATCH` tags (e.g. `v1.0.0`, `v1.1.0`). The tag string is what
appears in the release title. Optionally bump `MARKETING_VERSION` in the Xcode
project to match before tagging.

## Build it locally (without a release)

To produce the same shareable zip on your own machine:

```bash
./EarthboundBattle/package-for-sharing.sh
# output: EarthboundBattle/dist/EarthboundBattle-Screensaver.zip
```

To just build and install the screensaver locally for testing (no zip):

```bash
./EarthboundBattle/install-saver.sh
```

## What a recipient does

1. Download and unzip `EarthboundBattle-Screensaver.zip`.
2. Right-click **Install.command** → **Open** (approve the unidentified-developer prompt).
3. **System Settings → Screen Saver →** pick **EarthboundBattle**.

The saver runs on macOS 12 (Monterey) and later, on both Apple Silicon and Intel.

## Troubleshooting the CI build

- **`xcodebuild: scheme not found`** — the shared scheme
  (`EarthboundBattle.xcodeproj/xcshareddata/xcschemes/EarthboundBattle.xcscheme`)
  must be committed (it is). Schemes under `xcuserdata/` are machine-specific and
  ignored by git.
- **SDK / deployment-target errors** — the project targets macOS 12.0, so any recent
  Xcode on the runner can build it. The workflow selects the latest stable Xcode.
- **Release not created** — confirm the workflow has `permissions: contents: write`
  (it does) and that the tag/commit includes both the workflow and the project.
