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

R1 — Committed clean source before build. The coordinator commits only its
verified source, documentation and assets before invoking the publisher. The
script rejects any tracked, staged or untracked working-tree change, runs
`xcodegen generate`, then checks cleanliness again; it never auto-stages or
commits another session's work. Generated project drift must be reviewed and
committed by its owner before retrying. Archive, tag, install image and GitHub
Release all derive from that clean commit. The script records `SOURCE_COMMIT`
and aborts if HEAD moves or the tree goes dirty afterwards. It never uses
`git stash`, `git reset --hard`, `git clean` on source, or moves foreign changes
out of the checkout. An existing version tag is verified before the costly
build/notarization and must already point at that commit; tags are immutable.

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
artifacts below. `--local-only` requires the same clean committed source
(per R1) but makes **no remote writes**: no push, no tag push, no GitHub
Release changes.

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
roll back, re-sign, or re-notarize because of it. The appcast stage, diff
and commit must name only `appcast.xml`; unrelated staged files created during
notarization/publication must remain staged and must never enter that commit.

R7 — Build identity. The archive builds universal (`ARCHS="arm64 x86_64"`,
`ONLY_ACTIVE_ARCH=NO`) and the script verifies the universal binary with
`lipo`. Before notarization it asserts the built bundle's
`CFBundleShortVersionString` / `CFBundleVersion` equal the configured
`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.

## Routes

```bash
scripts/publish-release.sh --dry-run      # preflight only, no writes
scripts/publish-release.sh --local-only   # detached: clean committed source, signed+notarized DMG + ZIP, no remote writes
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
2. Require a clean committed tree, run `xcodegen generate`, reject generated
   drift, record `SOURCE_COMMIT`, and verify the version tag (an existing
   tag must equal `SOURCE_COMMIT`). `scripts/test-release-worktree.sh`
   exercises clean, modified, staged, untracked (including hidden-by-config)
   and ignored-build fixtures, plus appcast-only commits with unrelated staged work.
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

## Interrupted 1.0.17 preparation (2026-10-27)

The persistence refactor and floating character count passed the complete local
gate (112 tests / 142 executions; clean universal Debug/Release build/analyze).
Source `68d5287` was installed and its fresh mixed CJK/emoji file-open path
captured. Before publication, a concurrent owner-approved icon integration
started. The old publisher automatically committed that session's requirement
doc and taskboard as `c5d67b2` and created the local `v1.0.17` tag before archive.
The coordinator stopped that publisher before export, notarization or remote
publication. No public 1.0.17 was produced; do not move or publish that local tag.
The next complete release uses 1.0.18 and the completed icon assets.

This exposed an unsafe release-tooling assumption: a dirty checkout is not an
approved release snapshot. R1 now rejects dirty source instead of sweeping other
sessions' changes into a commit. Preserve the existing snapshot/history; do not
amend, revert or discard another session's work to recover.

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

## 1.0.18 publication evidence (2026-10-27)

Published [v1.0.18](https://github.com/NeatMacApps/NeatEditor/releases/tag/v1.0.18)
from immutable source `5818fac7fec5101cfdfe8be915311596d46af12b`; the appcast
commit is `a1c2aac`. This includes the persistence cleanup, floating character
count and approved serif-N icon. The complete integrated gate passed 112 tests /
142 executions with zero failures, skips or structured runtime warnings. Clean
Debug/Release build and analysis plus the release archive compiled all 41 app
Swift sources for arm64 and x86_64. Logs, input/environment fingerprints and
structured results are in `build/refactor-1.0.18/`; the full publisher log is
`build/release-logs/publish-20261027-102415.log`. Xcode 27.2 (27B5028f), macOS
27.2 (26B118), Swift 6 mode, Sparkle 2.9.5 and deployment target 26.0 were used.
The sole retained diagnostic is the AppIntents notice individually assessed in
[code-review.md](docs/code-review.md#sidebar-review-2026-10-24).

Apple accepted app submission `1e0daf4d-b909-416f-897a-7ead020dff48` and DMG
submission `f11c9686-b275-484b-930d-fda72d57fab1`. Both tickets were stapled.
Independent full anonymous downloads matched the local three-file asset set
byte-for-byte, including SHA256SUMS. Published fingerprints:

| Asset | SHA256 |
|---|---|
| `NeatEditor-1.0.18.dmg` | `e0a678036dd0e571629b24b8aa6430a85c22bfbe3535ef7a952422e2b7e7792f` |
| `NeatEditor-1.0.18.zip` | `aa03fd782e729c7f8e0ecd7f0db1d5771838b080f86e34be5844a1beb5b13a90` |

The live installed SUFeedURL serves build 18 with the expected URL, length and
bilingual notes. Ed25519 verification accepted the downloaded update and rejected
a one-byte-modified fixture. The latest-release route and release notes match.

The app from the anonymously downloaded DMG was installed at
`/Applications/NeatEditor.app` with the same Developer ID identity and launched
as PID 22718. Strict nested signature and stapled-ticket validation passed.
Its executable SHA256 is
`5507941771a7409f8ae8584e478c19544f1f83dc1c7ad7c7c33e9a69bf057c08`;
the executable, ICNS and Assets.car exactly match the exported release.
The decoded installed icon was inspected against the approved artwork.
Gatekeeper returned `source=Notarized Developer ID` with
`override=security disabled`: this verifies signatures/tickets, not ordinary
clean-machine enforcement. No security preference changed.

Fresh inspected captures show restored documents and a newly opened mixed
English/CJK/emoji fixture with aligned line numbers and the expected 54-character
floating count. The native File > Close Tab accessibility action removed the
fixture, and the original selected tab was restored. Evidence:
`published-installed.png`, `published-fixture.png`, `published-restored.png`,
installation receipts and public-verification JSON in the gate directory.
The session was locked: pointer input, physical IME, Settings, appearance variants,
motion, native Intel and minimum-macOS runtime execution were not reaccepted.
The DMG was ejected; no virtual display was connected.

Post-publication tooling follow-up changes only the appcast commit boundary:
the script's diff and `git commit --only` explicitly name `appcast.xml`.
Eight native Git fixtures, including a commit and a no-op with unrelated staged
work, pass with that work preserved. This main-branch tooling fix is newer than
the immutable release tag and does not change published application bytes.

## 1.0.19 publication evidence (2026-10-27)

Published [v1.0.19](https://github.com/NeatMacApps/NeatEditor/releases/tag/v1.0.19)
from immutable source `6b219ee894eebd183eed64dabbc322a8375af73b`; the appcast
commit is `aa068cd`. Scope: blank titlebar routing to the native window frame
and the first tab's continuous join beside the sidebar (`c08f65b`). Before the
version bump, the complete Debug suite passed (115 tests in 17 suites); the only
build/archive diagnostic was the AppIntents notice individually assessed in
[code-review.md](docs/code-review.md#sidebar-review-2026-10-24). Publisher log:
`build/release-logs/publish-20261027-145823.log`. Apple accepted app submission
`65bb402e-99e5-4c23-a57e-19b4d9a097d0` and DMG submission
`d4883431-92f6-4a34-863b-e1c6b93ebe5f`.

Anonymous downloads of the three assets matched SHA256SUMS and the local bytes;
the Release is published, `releases/latest` resolves to v1.0.19, and the raw
appcast serves build 19 with the ZIP's exact length.

| Asset | SHA256 |
|---|---|
| `NeatEditor-1.0.19.dmg` | `1f2d21fae36edec55e199c87b97104eca7eea3a10f556cb803266bd27cea6a42` |
| `NeatEditor-1.0.19.zip` | `37fda2f1c9ba351eb41ec2343832c491f2d750d55fd294418651cd3f072bd39d` |

The app from the downloaded DMG is installed at `/Applications/NeatEditor.app`
with the same Developer ID identity; strict signature and stapled-ticket checks
pass (`spctl`: `source=Notarized Developer ID`, `override=security disabled`).
Executable SHA256 `91ef4af48a665c353956f6967206ab2aff34f061411ff7c4aa6eddc7536a1282`.
A fresh window capture showed the first tab's foot and a short top-rule run meeting
the sidebar edge without a break; the pre-release local build was also captured
with the sidebar collapsed. Pointer interaction and appearance variants were not
reaccepted.

## 1.0.20 and 1.0.21 corrections (2026-10-27)

1.0.19 shipped two owner-visible regressions that inactive-window acceptance
missed: the 8 pt first-tab clearance showed a stray band-colored column, and the
opaque titlebar adopted for blank-titlebar routing clipped every selected tab's
corner arcs and capped the sidebar with a white titlebar section background in
the key window. Root causes and decisions are in
[TabStripGestures.md](TabStripGestures.md).

- [v1.0.20](https://github.com/NeatMacApps/NeatEditor/releases/tag/v1.0.20):
  corner arcs rejoined and first-tab clearance reduced to the 3 pt foot. Source
  `2190fdb`; appcast commit `41ed28c`; Apple submissions
  `d78e0227-5408-4918-8b9c-f73f1b674786` (app) and
  `919df3ce-0479-4b79-93f1-9f44913705d3` (DMG). The publisher's final feed check
  timed out on raw-CDN lag (R6); a later anonymous read served build 20 and the
  Release held exactly the three assets.
- [v1.0.21](https://github.com/NeatMacApps/NeatEditor/releases/tag/v1.0.21):
  transparent `.hiddenTitleBar` scene restored with blank-titlebar routing kept
  native. Source `8cfa0e0`; appcast commit `29d6701`; Apple submissions
  `e7890000-67fa-444b-a568-d5a6bc82d5bf` (app) and
  `61b93e8c-73ea-4c17-8db8-d7b6d31d85c9` (DMG). Anonymous downloads matched
  SHA256SUMS and local bytes; `releases/latest` and the raw appcast serve 1.0.21 /
  build 21. DMG `a657038484e77ea326a9eb6eadc420ba1c8162fbdc8f7266e48ffffa30bab549`,
  ZIP `9bb0983ce703203aa2538b036bf8f47363adb858ae206eb340cac3a2d832b988`.
  Installed from the public DMG (same Developer ID; strict signature and staple
  pass); executable SHA256 `a6ff08c7e625a0e46ffbc73e4df6e12a0a6f631f26de66097baf555222c307c4`.
- Evidence: 116 tests in 17 suites; installed-window pixel reads of both
  selected-tab corners and the first tab with the sidebar expanded and collapsed;
  a debuggable ad-hoc copy of the same source (never installed) confirmed in the
  real SwiftUI scene that the titlebar is transparent, both titlebar section
  backgrounds are hidden, and blank points above the sidebar and tabs hit the
  window frame view while buttons, tabs, list and editor keep their hits.
- Limit and lesson: the session was locked, so every capture was of an inactive
  window. The key-window cap was established structurally, not by an active
  pixel capture. Titlebar, glass and material changes need key-window evidence
  (owner capture or an unlocked session) before release; an inactive capture
  alone is not acceptance for them.

## 1.0.22 full-width tab rule (2026-10-27)

The owner clarified the original report: the tab bar's bottom line must continue
left across the sidebar (see "Full-width tab rule" in
[TabStripGestures.md](TabStripGestures.md)); 1.0.19-1.0.21 had fixed adjacent
defects but not this. [v1.0.22](https://github.com/NeatMacApps/NeatEditor/releases/tag/v1.0.22)
moves the rule to the split view (full width, above both panes) and paints the
band color behind the transparent titlebar in the editor column. Source
`ab2c237`; appcast commit `deaad15`; Apple submissions
`13c6cfa0-1d6e-44f9-b729-80e3bcd63560` (app) and
`29294660-be5f-4a0a-b251-48eb9d4dab07` (DMG). Anonymous downloads matched
SHA256SUMS and local bytes; DMG `f40cf9a36288814a3f2f6189af0fe70d97dac7d071d8c180e79bd3684275e65c`,
ZIP `3dfcd07bd93c079cb7986f0c92287fa00cdb970756101c9c971f7bee342aa3f1`. The raw
feed lagged on build 21 for about a minute after the push (R6) and then served
build 22. Installed from the public DMG; executable SHA256
`3e92d1e629fd86c5b860669de3c1a34c729d27e2bdcdcfa54dd537cfc222fc48`.
117 tests passed. Inactive installed pixels: the rule runs from the window's
leading edge over the sidebar and the editor column; the editor surface is intact.

A first build of this change filled `dirtyRect` in the new band background view
and blanked the whole editor; the capture caught it before release. With
`clipsToBounds` off by default, fill `bounds`, never `dirtyRect`.

Remaining limit: still no key-window capture. Inactive pixels show the run over
the sidebar slightly darker (the system's own sidebar edge line overlaps it
only when inactive).

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
