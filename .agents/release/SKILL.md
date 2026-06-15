---
name: release
description: Cut a new versioned release of the EarthboundBattle macOS screensaver — bump the version, generate the release notes, push the tag, and let CI build & publish the .saver zip. Use when the user wants to "make a release", "cut a release", "ship a new version", "publish a release", or runs /release.
---

# Release the EarthboundBattle screensaver

Releases are built and published by GitHub Actions
(`.github/workflows/release.yml`). Pushing a `vX.Y.Z` tag spins up a macOS runner
that builds a **universal**, ad-hoc-signed `.saver`, packages it into
`EarthboundBattle-Screensaver.zip` (via `EarthboundBattle/package-for-sharing.sh`),
and attaches it to a GitHub Release whose notes come from **`RELEASE_NOTES.md`**
(`body_path`). This skill prepares the version + notes and starts that flow.

No Apple Developer account is needed — the build is ad-hoc signed, so downloaders do
a one-time "Open anyway" step (documented in the notes).

## Steps

1. **Preflight — never release from a dirty or wrong branch.**
   - `git rev-parse --abbrev-ref HEAD` → must be `main`. If not, stop and confirm with the user.
   - `git status --porcelain` → must be empty. If there are uncommitted changes, stop and ask what to do.
   - `git pull --ff-only` to sync with origin.

2. **Pick the next version.**
   - Latest tag: `git tag --list 'v*' --sort=-v:refname | head -1` (e.g. `v1.1.0`).
   - Ask the user whether this is a **patch**, **minor**, or **major** bump (or let them give an explicit version). Rule of thumb: **minor** when features were added, **patch** for fixes only. Compute the next `vMAJOR.MINOR.PATCH`.
   - Verify the tag doesn't already exist (`git tag --list vX.Y.Z` empty, `gh release view vX.Y.Z` 404). If it exists, stop and confirm.

3. **Bump the bundle version.** In `EarthboundBattle/EarthboundBattle.xcodeproj/project.pbxproj`, set **both** `MARKETING_VERSION` lines to the new `MAJOR.MINOR.PATCH` (no leading `v`).

4. **Write the release notes.** Rewrite the `## What's new in vX.Y.Z` section of `RELEASE_NOTES.md`:
   - Gather user-facing changes since the last tag: `git log <lastTag>..HEAD --oneline`.
   - Summarize them as short, user-facing bullets (what changed for someone using the screensaver, not internal refactors). Keep the intro line, the **Install** section, and the un-notarized footer intact.

5. **Commit & push to main.**
   - `git add EarthboundBattle/EarthboundBattle.xcodeproj/project.pbxproj RELEASE_NOTES.md`
   - `git commit -m "release vX.Y.Z"` (end the message with the Co-Authored-By trailer).
   - `git push origin main`

6. **Create the tag and start the release with gh.**
   - `gh release create vX.Y.Z --target main --title "Earthbound Battle Backgrounds Screensaver vX.Y.Z" --notes-file RELEASE_NOTES.md`
   - This creates the `vX.Y.Z` tag and the GitHub Release, which triggers the workflow to build and attach `EarthboundBattle-Screensaver.zip`. The workflow re-publishes the same notes from `RELEASE_NOTES.md`, so there's no conflict.

7. **Monitor and report.**
   - `gh run list --workflow=release.yml --limit 1` then `gh run watch <run-id>` (the build takes a few minutes on a macOS runner).
   - When it succeeds, confirm the asset is attached: `gh release view vX.Y.Z` and report the release URL to the user.

## Guardrails

- A pushed tag / published release is hard to retract once others pull it — confirm the version with the user before step 6.
- Don't overwrite an existing release for the same tag; pick a new version instead.
- If the workflow fails, see the **Troubleshooting** section of `RELEASE.md`.
