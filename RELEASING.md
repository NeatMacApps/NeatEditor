# Releasing NeatEditor

Authoritative public route: a Developer ID-signed + notarized local release
built by `scripts/publish-release.sh` on the maintainer Mac. The tag CI
workflow (`.github/workflows/release.yml`) is **validation only**: it builds
the tagged source, verifies the universal binary and packages, and keeps
them as private workflow artifacts. It never creates, uploads to, or
modifies a public GitHub Release.

## Durable release requirements

R1 — Snapshot before build. The script runs `xcodegen generate`, then
commits the generated project together with the whole workspace
(`git add -A`, including other agents' unfinished source) *before*
`xcodebuild` archives. Archive, tag, install image, and GitHub Release
all derive from that commit. It records the built `SOURCE_COMMIT`
fingerprint and aborts if `HEAD` moves or the tree goes dirty afterwards.
It never uses destructive isolation (`git stash`, `git reset --hard`,
`git clean` on tracked source, worktree moves of foreign changes).
A dirty tree is committed, not discarded. The pre-existing tag for the
version is verified **before** the costly build/notarization: an existing
tag must point at the snapshot commit (tags are immutable); otherwise
the script aborts instead of moving it.

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
artifacts below. `--local-only` still takes a local source snapshot commit
(it must, per R1) but makes **no remote writes**: no push, no tag push, no
GitHub Release changes.

R4 — Public asset set and draft discipline. A public Release `vX.Y.Z`
must contain exactly the signed set, all from the tagged commit:
`signed + notarized + stapled DMG` (first install),
`Sparkle-signed update ZIP` (built from the stapled app),
`SHA256SUMS.txt` covering both. Only signed artifacts are a public
install path: older CI-built `*-macOS-universal.*` assets still visible on
past Releases (e.g. v1.0.3) are unsigned placeholders, not installs.
The script creates the Release as a **draft**, uploads the three files one
by one with read-back, asserts the final asset set, and only then
publishes (`gh release edit --draft=false`). A failed upload leaves a
draft, never an empty or unsigned Latest. Retrying from the exact same
source is safe: the immutable-tag check (R1) guarantees the tag still
matches, and an existing draft for the tag is reused. Release notes are
bilingual (English first, Simplified Chinese second) with real newlines;
the English body is the `CHANGELOG.md` section for the version, which
must exist. `CURRENT_PROJECT_VERSION` must be strictly greater than the
live appcast's `<sparkle:version>`.

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

R7 — Build identity. The archive builds universal (`ARCHS="arm64 x86_64"`,
`ONLY_ACTIVE_ARCH=NO`) and the script verifies the universal binary with
`lipo`. Before notarization it asserts the built bundle's
`CFBundleShortVersionString` / `CFBundleVersion` equal the configured
`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.

## Routes

```bash
scripts/publish-release.sh --dry-run      # preflight only, no writes
scripts/publish-release.sh --local-only   # detached: local snapshot commit, signed+notarized DMG + ZIP, no remote writes
scripts/publish-release.sh                # detached: full local build + draft Release + publish + appcast
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
   the committed appcast's build number, `CHANGELOG.md` has a section for
   the version, clean merge/rebase state, single-instance lock (same
   worktree never runs two publishes; the lock's parent dir is created
   only on a real run, never during `--dry-run`).
2. `xcodegen generate`, then commit-first snapshot (`git add -A` +
   commit when dirty), record `SOURCE_COMMIT`, verify the version tag
   (existing tag must equal `SOURCE_COMMIT`).
3. Universal Release archive + Developer ID export, bundle
   marketing/build number assert, Sparkle nested-component re-sign
   inside-out, EdDSA key match, signature/hardened-runtime/
   timestamp/`get-task-allow` self-checks.
4. Notarize app zip → staple → re-zip the **stapled** app for Sparkle →
   `generate_appcast` (EdDSA-signed, embedded bilingual notes, XML +
   signature asserts).
5. Build DMG → notarize → staple → `spctl -a -t install` +
   `stapler validate` + `SHA256SUMS.txt` over DMG + ZIP.
6. Full route only: tag the built commit, push branch + tag (tag push
   retried once), create the Release as a **draft** with bilingual
   CHANGELOG-based notes, upload signed files one by one with read-back,
   assert the final asset set, publish the Release, commit + push the
   appcast, anonymous download + XML + build-number verification
   (raw-CDN-lag tolerant retry).

## Ownership split (no contradictions)

The script performs the mechanical release steps above, including tag,
push, draft creation, uploads, and publishing. The coordinator owns
triggering the run, the local install + launch acceptance, and all
recovery decisions (credential/account states, retry vs abort). The
script never decides product scope and never touches public Releases
outside the R4 draft flow.

## Coordinator handoff

```bash
ditto "build/release/export/NeatEditor.app" "/Applications/NeatEditor.app"  # after pkill + rm old .app
open "/Applications/NeatEditor.app"                                          # retry twice before reporting failure
xcodebuild -project "NeatEditor.xcodeproj" -scheme "NeatEditor" \
  -configuration Debug -destination 'platform=macOS' test                   # unit tests: text sync, persistence, autosave, failure paths, composition, preferences
```

## References

- Apple: [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
  (`notarytool submit`, polling `info`, `stapler staple`, `spctl`).
- Sparkle: [Publishing an update](https://sparkle-project.org/documentation/publishing/)
  (`ditto -c -k --sequesterRsrc --keepParent`, `generate_appcast`,
  EdDSA `edSignature`, machine-readable `sparkle:version`).
- GitHub: [Releases REST API](https://docs.github.com/en/rest/releases/releases),
  [least-privilege GITHUB_TOKEN permissions](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/controlling-permissions-for-github_token)
  (validation workflow uses `contents: read`; `upload-artifact` keeps
  packages as login-gated workflow artifacts, see
  [actions/upload-artifact](https://github.com/actions/upload-artifact)).
- Workspace: `~/Codes/_standards/workspace-docs/swift-docs/macos-signing-notarization-distribution.md`
  (route A archive+export, self-checks, no `--deep`, no `setsid`).
