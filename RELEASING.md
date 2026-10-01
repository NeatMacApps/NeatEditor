# Releasing NeatEditor

Authoritative public route: a Developer ID-signed + notarized local release
built by `scripts/publish-release.sh` on the maintainer Mac. The tag-driven
GitHub Actions workflow (`.github/workflows/release.yml`) only builds
**unsigned** placeholders and is never the public install path.

## Durable release requirements

R1 — Commit before package. The script snapshots the whole workspace
(`git add -A`, including other agents' unfinished source) into a commit
*before* `xcodegen`/`xcodebuild` run, and the archive, tag, install image,
and GitHub Release all derive from that commit. It records the built
`SOURCE_COMMIT` fingerprint and aborts if `HEAD` moves or the tree goes
dirty afterwards. It never uses destructive isolation (`git stash`,
`git reset --hard`, `git clean` on tracked source, worktree moves of
foreign changes). A dirty tree is committed, not discarded.

R2 — Detached notarization wait. Notarization polls for tens of minutes.
The script re-launches itself detached via Python
`subprocess.Popen(..., start_new_session=True)` (survives coordinator /
terminal exit), never macOS `setsid` (does not exist), never a bare
`nohup ... &` under the caller's session. It prints the log path and child
PID and records the PID in `build/release-logs/publish-latest.pid`.

R3 — Local install needs no notarization. Launchability / local overwrite
install (`ditto` a committed-tree build to `/Applications/NeatEditor.app`)
works without waiting for notarization; the coordinator performs the
actual install and launch acceptance. Notarization gates only the *public*
artifacts below.

R4 — Public asset set. A public Release `vX.Y.Z` must contain exactly the
signed set, all from the tagged commit:
`signed + notarized + stapled DMG` (first install),
`Sparkle-signed update ZIP` (built from the stapled app),
`SHA256SUMS.txt` covering both. Unsigned CI placeholders
(`*-macOS-universal.*`) are deleted from the Release before upload, never
shipped, never left beside signed files. Release notes are bilingual
(English first, Simplified Chinese second) with real newlines.
`CURRENT_PROJECT_VERSION` must be strictly greater than the live
appcast's `<sparkle:version>`. A tag that already exists must point at the
built commit (tags are immutable); otherwise the script aborts instead of
moving it.

R5 — Portability and secrets. The script stays runnable under macOS
`/bin/bash` 3.2 (no associative arrays, no `${var,,}`, no `readarray`).
Signing identity, team, and notary key defaults are unchanged; the script
never prints secret values or key file contents (only file paths and
Apple submission IDs).

R6 — Appcast / tag sequencing. Tag points at the built source commit; the
appcast update commit (`chore: 发布 vX.Y.Z 更新清单`) lands on `main`
*after* the tag + signed uploads succeed. If the anonymous re-check still
sees the old `<sparkle:version>` at the raw CDN URL while the repo source
already has the new one, that is CDN lag: wait and re-check only. Never
roll back, re-sign, or re-notarize because of it.

## Routes

```bash
scripts/publish-release.sh --dry-run      # preflight only, no writes
scripts/publish-release.sh --local-only   # detached: signed+notarized DMG + ZIP, no git/remote writes
scripts/publish-release.sh                # detached: full local build + GitHub Release + appcast
scripts/publish-release.sh --foreground --dry-run   # foreground preflight (debugging only)
```

Detached launch prints `log path + PID`, e.g.
`build/release-logs/publish-*.log (pid NNNN)`. Follow with `tail -f`.
Helper `scripts/run-detached.py` performs the detach; it is also usable
for other long local jobs.

## What the script does, in order

1. Preflight: Developer ID certificate present, notary `.p8` key + API
   credentials live (`notarytool history` reachable), SemVer
   `MARKETING_VERSION`, positive-integer `CURRENT_PROJECT_VERSION` above
   the committed appcast's build number, clean merge/rebase state,
   single-instance lock (same worktree never runs two publishes).
2. `xcodegen generate`, then commit-first snapshot (`git add -A` +
   commit when dirty), record `SOURCE_COMMIT`.
3. Release archive + Developer ID export, Sparkle nested-component
   re-sign inside-out, EdDSA key match, signature/hardened-runtime/
   timestamp/`get-task-allow` self-checks.
4. Notarize app zip → staple → re-zip the **stapled** app for Sparkle →
   `generate_appcast` (EdDSA-signed, embedded bilingual notes, XML +
   signature asserts).
5. Build DMG → notarize → staple → `spctl -a -t install` +
   `stapler validate` + `SHA256SUMS.txt` over DMG + ZIP.
6. Full route only: tag the built commit (existing tag must match),
   push branch + tag, wait out any in-progress CI `Release` run for the
   tag, create the empty Release with bilingual notes, delete unsigned
   CI placeholder assets, upload signed files one by one with read-back,
   commit + push the appcast, anonymous download + XML + build-number
   verification (raw-CDN-lag tolerant retry).

## Coordinator handoff (delivery owned by coordinator)

The script never installs, tags-by-hand, or publishes on its own beyond
the steps above; remaining delivery commands after a green script run:

```bash
ditto "build/release/export/NeatEditor.app" "/Applications/NeatEditor.app"  # after pkill + rm old .app
open "/Applications/NeatEditor.app"                                          # retry twice before reporting failure
xcodebuild -project "NeatEditor.xcodeproj" -scheme "NeatEditor" \
  -configuration Debug -destination 'platform=macOS' test                   # 18 tests: text sync, persistence, preferences
```

## References

- Apple: [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
  (`notarytool submit`, polling `info`, `stapler staple`, `spctl`).
- Sparkle: [Publishing an update](https://sparkle-project.org/documentation/publishing/)
  (`ditto -c -k --sequesterRsrc --keepParent`, `generate_appcast`,
  EdDSA `edSignature`, machine-readable `sparkle:version`).
- GitHub: [Releases REST API](https://docs.github.com/en/rest/releases/releases),
  [job dependencies](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-jobs)
  (empty release first, one-file uploads with read-back).
- Workspace: `~/Codes/_standards/workspace-docs/swift-docs/macos-signing-notarization-distribution.md`
  (route A archive+export, self-checks, no `--deep`, no `setsid`).
