# Releasing NeatEditor

Authoritative public route: a Developer ID-signed + notarized local release
built by `scripts/publish-release.sh` on the maintainer Mac. The tag CI
workflow (`.github/workflows/release.yml`) is **validation only**: it builds
the tagged source, verifies the universal binary and packages, and keeps
them as login-required workflow artifacts (for a public repo any signed-in
person with access can download them: authentication is access control,
not confidentiality). It never creates, uploads to, or
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
Before any upload the script queries the tag's Release page: an existing
page must be a draft (`isDraft=true`) or the script stops. An
already-published page is never mutated — the only allowed path is a
strictly read-only already-complete check (exact three-file set, then
downloaded bytes verified), after which the script proceeds directly to
the appcast step. "Exact" means whole-set string comparison of the three
expected basenames as fixed strings: near-name matches and any extra
file fail. The script creates a missing page as a **draft**, uploads the
three files one by one with read-back, asserts the exact set, then
downloads the draft assets (authenticated `gh release download` into a
disposable directory) and compares bytes (`cmp`) plus SHA256 against the
locally verified three — names alone never suffice. Only then does it
publish (`gh release edit --draft=false`). Any failure before that point
dies with the page left as a draft; no failure path publishes. Retrying
from the exact same source is safe: the immutable-tag check (R1)
guarantees the tag still matches, and an existing draft for the tag is
reused. Release notes are bilingual (English first, Simplified Chinese
second) with real newlines; the body is the `CHANGELOG.md` section for
the version, which must exist. `CURRENT_PROJECT_VERSION` must be strictly
greater than the live appcast's `<sparkle:version>`.

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
3. Universal Release archive + Developer ID export, retaining complete
   compiler and export diagnostics. Xcode signs the nested Sparkle
   components during export; do not manually re-sign the exported app.
   Assert bundle marketing/build numbers, EdDSA key match, and each
   executable's signature, hardened runtime, timestamp and absence of
   `get-task-allow`, following [Sparkle's archive/export guidance](https://sparkle-project.org/documentation/).
4. Notarize app zip → staple → re-zip the **stapled** app for Sparkle →
   `generate_appcast` (EdDSA-signed, embedded bilingual notes, XML +
   signature asserts).
5. Build DMG → notarize → staple → `spctl -a -t install` +
   `stapler validate` + `SHA256SUMS.txt` over DMG + ZIP.
6. Full route only: tag the built commit, push branch + tag (tag push
   retried once), create the Release as a **draft** with bilingual
   CHANGELOG-based notes (an existing page must be a draft; a published
   page is never mutated), upload signed files one by one with read-back,
   assert the exact three-file set, download-verify bytes + SHA256, then
   publish the Release, commit + push the appcast, anonymous download +
   XML + build-number verification (raw-CDN-lag tolerant retry).

## Ownership split (no contradictions)

The script performs the mechanical release steps above, including tag,
push, draft creation, uploads, and publishing. The coordinator owns
triggering the run, the local install + launch acceptance, and all
recovery decisions (credential/account states, retry vs abort). The
script never decides product scope and never touches public Releases
outside the R4 draft flow.

Owner-directed publication is time-sensitive. Bound the pre-trigger
acceptance to one fresh installed window frame plus the command-driven
flows the locked session can exercise, record any pointer/Settings limits
as deferred, and start the train; do not spend tens of minutes on
unattended acceptance attempts. The 1.0.16 release spent about 30 minutes
on pre-trigger acceptance for a roughly 7-minute publication, and the owner
asked for direct publication to move faster.

## Coordinator handoff

```bash
ditto "build/release/export/NeatEditor.app" "/Applications/NeatEditor.app"  # after pkill + rm old .app
open "/Applications/NeatEditor.app"                                          # retry twice before reporting failure
xcodebuild -project "NeatEditor.xcodeproj" -scheme "NeatEditor" \
  -configuration Debug -destination 'platform=macOS' test                   # unit tests: text sync, persistence, autosave, failure paths, composition, preferences
```

## Publication-only recovery

When Git transport fails **after** accepted/stapled artifacts exist, preserve the
source commit, immutable tag, app, DMG, ZIP and SHA256SUMS. Re-validate signatures,
tickets, hashes and the tag's source identity; do not re-archive, re-sign or
resubmit notarization just to retry GitHub publication.

The 1.0.14 SSH push failed before remote publication. A per-command HTTPS push
using `git -c credential.helper= -c 'credential.helper=!gh auth git-credential'`
and the public repository URL preserved existing hooks and required no secret in
arguments or files. It changed no global Git or network configuration. Only the
publication stage was resumed: push branch/tag, reuse the existing R4 helpers,
upload to a draft, download/compare all three assets, then publish and push the
appcast. The original temporary appcast had been cleaned on exit, so its metadata
was regenerated from the **unchanged** signed ZIP and bilingual CHANGELOG notes;
DMG/ZIP bytes were not rebuilt. Anonymous full downloads and the live build-14
feed were independently checked afterward.

The 1.0.15 run failed later: a TCP reset interrupted the update-ZIP upload after
the draft already held the DMG. Publication resumed from the same `98784c7`
snapshot: signatures, tickets, hashes and tag identity were revalidated, the
existing three files were uploaded with `--clobber`, downloaded and compared
byte-for-byte, the draft was published, and the appcast was regenerated from the
unchanged signed ZIP. Other agents began editing app sources after the snapshot,
so the resume did not require a clean tree; it staged only `appcast.xml` and left
their in-progress files uncommitted. It did not stash, reset, rebuild, re-sign or
resubmit notarization. The live build-15 feed and an install from the public DMG
were verified afterward.

Follow-up (not implemented here): provide a maintained publish-only resume mode
with persistent source/asset fingerprints and generated appcast. Both recoveries
(1.0.14 for SSH, 1.0.15 for attachment upload) used ad hoc scripts; the maintained
mode should own draft state and appcast regeneration. The workaround above is
evidence-backed recovery, not an instruction to silently rerun the whole
archive/notarization pipeline after a transport failure.

## 1.0.16 train gate (2026-10-26, owner-directed publication)

Source `b7e2398` prepares version 1.0.16 / build 16 and English-first bilingual
notes for the committed changes after 1.0.15. The publisher's dry run passed
certificate, notary credentials and version checks. The full publisher was not
started: no 1.0.16 tag, notarization submission, public assets or appcast change
was created by that gate attempt. At that point, the last public release was 1.0.15.

The gate found an AppKit runtime error that successful tests had not rejected:
the empty toolbar delegate lacked its required item factory. The existing native
controller now supplies that method; the compact-row regression checks that
AppKit can call it. The same 98-test arm64 suite passes without the original
`invalid delegate` runtime diagnostic. Universal Debug and Release build/analyze
pass, including both arm64 and x86_64 compilation. Complete logs and structured
results are in `build/release-train-1.0.16/`. The sole retained diagnostic is the
AppIntents metadata notice individually assessed in
[code-review.md](docs/code-review.md#sidebar-review-2026-10-24); no Swift compiler
or static-analysis issue was reported. Toolchain: Xcode 27.2 (27B5028f), macOS
27.2 (26B5112a). Intel and minimum-macOS runtime execution remain unverified.

The committed Developer ID-signed universal Release was installed at
`/Applications/NeatEditor.app` and launched from there. Its executable SHA256
matches the build product (`0330d248474378ae12b219ef1fb38a62050582d9727d830dadc736c5395db252`),
and strict bundle signature verification passes. This is a local unnotarized
build, not a published installation.

Real-path acceptance was retried on the same installed build (PID 63720,
window 4500) while the session stayed locked (since 02:29). The earlier capture
failure was display timing, not permission: `winshot.py capture --wake` returned
an isolated 1164 × 877 pt frame on the first call
(`build/release-train-1.0.16/installed-window-now.png`), and every later capture
in this session did too. The inspected frames show the single 40 pt row with
system traffic lights, the sidebar toggle beside them, equal document tabs with
their stepped join, New Document and pin at the trailing end, the expanded and
collapsed sidebar, the search bar, and two documents with aligned line numbers.
Keyboard events posted to the app PID (`CGEvent.postToPid`) reach the menus even
though the app is not frontmost: View > Toggle Sidebar collapsed and restored the
sidebar, New created a blank document tab, Close Tab removed it, Reopen Closed Tab
restored it, Find opened the search bar, and opening `~/Documents/软考笔记`
selected its existing tab without duplicating it (`sidebar-toggle-1.png`,
`new-document.png`, `close-tab.png`, `reopen-tab.png`, `open-existing-file.png`).

Pointer acceptance is still unavailable. Mouse events posted to the PID and AX
window requests do not reach the app (System Events reports zero windows and a
pointer click changes nothing), because a locked session cannot make the app
frontmost or key. The Settings command creates its 500 × 500 window, but it stays
offscreen (`kCGWindowIsOnscreen = 0`), so its contents cannot be inspected. Still
unaccepted for this build: pointer tab click/rename/drag, the sidebar button
click, the pin button, divider and minimum-width resizing, Settings contents,
light/dark appearance and motion.

Owner instruction (2026-10-26): publish the latest version directly. The release
therefore proceeds with the pointer and Settings acceptance above deferred as a
post-release check. No archive or accepted public artifact existed to resume, so
the publisher starts from this committed source.

## 1.0.16 publication evidence (2026-10-26)

Published [v1.0.16](https://github.com/NeatMacApps/NeatEditor/releases/tag/v1.0.16)
from immutable source `4632fdd2bd438bc4ac78f3d67de50439474a0e85` (version
1.0.16 / build 16). This includes the owner-authorized scope through `8f8c801`
and only the release taskboard claim afterward. The prepared version and
English-first, complete Simplified Chinese CHANGELOG notes were reused; no app
source or dependency changed. The appcast commit is `0c5f8a4`.

Fresh clean Debug and Release builds and static analysis compiled all 37 app
Swift sources for arm64 and x86_64. The complete arm64 suite passed: 98 tests,
116 parameter-expanded executions, zero skipped or failed. Complete gate logs,
input/environment fingerprints and structured XCTest results are retained in
`build/release-train-publish-1.0.16/`. Xcode 27.2 (27B5028f), macOS 27.2
(26B5112a), Swift 6 mode, deployment target 26.0 and pinned Sparkle 2.9.5 were
used. The only build/archive diagnostic was the AppIntents metadata notice
individually assessed in [code-review.md](docs/code-review.md#sidebar-review-2026-10-24).
No Swift compiler or static-analysis issue was reported. Intel execution and
minimum-macOS runtime coverage remain unverified.

The maintained publisher completed archive/export, nested Developer ID and
hardened-runtime checks, both notarizations, app/DMG stapling, draft asset
byte comparison, publication and the appcast push. Its complete log is
`build/release-logs/publish-20261026-134700.log`. Apple accepted app submission
`6d83d72a-42a3-4b5f-b087-ad12228daeb6` and DMG submission
`d24a9692-9a58-46c4-b93e-556d4eb3e56b`.

Independent anonymous full downloads confirmed exactly three published assets,
matching local bytes and SHA256SUMS. SHA256 fingerprints:

| Asset | SHA256 |
|---|---|
| `NeatEditor-1.0.16.dmg` | `20ff7f84483c8b07345f951dd0be3a72f7036ff64f7c5a54a4b7bc5020503e50` |
| `NeatEditor-1.0.16.zip` | `17ccd24da0eab005febe2f078857d3868730750cafeec86132f8cf2b66f311c0` |

The normal anonymous SUFeedURL returned build 16 with the correct enclosure URL,
length and bilingual notes. The release body matches the CHANGELOG. The ZIP's
Ed25519 signature verified against the installed app's public key; changing one
byte made verification fail. The latest-release route identifies v1.0.16.

The app from that exact DMG was installed at `/Applications/NeatEditor.app`,
retaining the same Developer ID identity, and launched there as PID 59849.
The installed executable SHA256 is
`e889f7bb797329e06cbc4b57513c95350fd1f52498473abbad0778923bbce061`.
Strict nested signature and stapled-ticket validation passed. `spctl` returned
`source=Notarized Developer ID`, with `override=security disabled`: signatures
and tickets are verified, but this Mac does not establish normal Gatekeeper
enforcement. No security setting was changed. Final readback used PID 78415
at the same installed path with the same executable fingerprint.

Fresh isolated screenshots of windows 5377 and 5428 were inspected: the compact row,
system window controls, sidebar toggle, stepped tabs, New Document and pin are
present. Opening a temporary mixed English/Chinese file rendered its new text,
wrapped logical line 6, following line numbers and final empty line correctly.
Close Tab removed that fixture; opening the previously selected document
restored its existing tab. The actual View > Toggle Sidebar accessibility menu
action collapsed and restored the sidebar with matching captures. The original
`invalid delegate` diagnostic was absent from the new process log. Evidence is
in the same gate directory (`installed-window.png`, `installed-fixture.png`,
`installed-closed-fixture.png`, `installed-sidebar-menu.png`,
`installed-restored.png`, installation/public-verification receipts).

The session stayed locked. These are live file-open/menu-action and isolated
window checks, not physical keyboard/pointer or desktop-composited acceptance.
The owner's deferred pointer tab selection/rename/drag, sidebar-button click,
pin, divider/minimum-width resizing, Settings, appearance variants and motion
checks remain deferred. The temporary fixture tab was closed, the original
document/sidebar state restored and the task-mounted DMG ejected. No virtual
display was connected. Quitting and relaunching the installed published app
restored the persisted selection (`软考笔记`) together with its content; an
initial look at the cropped top row suggested the first tab was highlighted, but
the bold title and lighter tab background show `软考笔记` selected, so no content
crossed document identities.

## References

- Apple: [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
  (`notarytool submit`, polling `info`, `stapler staple`, `spctl`).
- Sparkle: [Publishing an update](https://sparkle-project.org/documentation/publishing/)
  (`ditto -c -k --sequesterRsrc --keepParent`, `generate_appcast`,
  EdDSA `edSignature`, machine-readable `sparkle:version`).
- GitHub: [Releases REST API](https://docs.github.com/en/rest/releases/releases),
  [least-privilege GITHUB_TOKEN permissions](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/controlling-permissions-for-github_token)
  (validation workflow uses `contents: read`; `upload-artifact` keeps
  packages as login-required workflow artifacts — for a public repo any
  signed-in person with access can download them, so authentication is
  access control, not confidentiality, see
  [actions/upload-artifact](https://github.com/actions/upload-artifact)).
- Workspace: `~/Codes/_standards/workspace-docs/swift-docs/macos-signing-notarization-distribution.md`
  (route A archive+export, self-checks, no `--deep`, no `setsid`).
