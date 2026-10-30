# macOS dual-channel distribution tools

A reusable XcodeGen include and dependency-free Python helper for **macOS**.
One source tree, two lightweight app targets: direct download with Sparkle, and
Mac App Store without Sparkle. [Research](RESEARCH.md) explains the tradeoffs.
[简体中文](README.zh-CN.md).

This is developer tooling, not a second editor, a runtime updater package, or a
complete publisher. NeatEditor's app targets, user data and release route are
unchanged. The example executable prints its channel and exits; it has no UI.

## Components

- `dual-channel.yml`: common app configuration, direct-only Sparkle dependency,
  store-only sandbox entitlement, explicit compilation conditions and channel
  Info.plist marker. Each channel defines Debug/Release conditions explicitly:
  configuration-level settings can override base settings in the same target.
- `distribution.py`: read-only `plan`, local `build` (archive + export), and
  read-only `audit` of real Mach-O files and signed entitlements.
- `example/`: a minimal two-target project and per-channel export options.
- `test_distribution.py`: hermetic contract/negative tests, using only Python's
  standard library. Native acceptance evidence is in [VERIFICATION.md](VERIFICATION.md).

## Install

Requires macOS, Xcode, XcodeGen and Python 3.11+. From this repository root:

```bash
chmod +x tools/macos-distribution/distribution.py
ln -s "$PWD/tools/macos-distribution/distribution.py" "$HOME/.local/bin/macos-distribution"
macos-distribution version
```

Ensure `~/.local/bin` exists and is on PATH first. `ln` deliberately refuses to
overwrite an existing installation; inspect it rather than forcing replacement.
Alternatively invoke `python3 /path/to/distribution.py` directly. The source
checkout is the installed tool's single authority; no PyPI dependencies or
credential copies are needed. Keep a pinned checkout for reproducible use.

## Adopt in another app

Include `dual-channel.yml` with `relativePaths: false`, following
[`example/project.yml`](example/project.yml). It can be referenced by absolute
path from a pinned checkout, so consumers do not need their own maintained copy.
An independently cloned consumer must provision that checkout explicitly; do not
assume this Mac's directory structure exists on CI or another developer's Mac.

1. Supply `app_name`, `bundle_id`, `app_sources`, `app_category` and app-specific deployment,
   version, team, localization and Info.plist settings. Direct builds also need
   the real HTTPS Sparkle feed and public key. Example values are placeholders,
   never production defaults. Existing apps should merge their actual Info.plist
   properties into both targets, not replace their existing document types.
2. Use `DistributionDirect` and `DistributionAppStore` as the two target
   templates. Only the direct target has a SwiftPM Sparkle dependency. Do not
   add Sparkle to a common target/template or remove frameworks after linking.
3. Gate imports and update controls with `#if DIRECT_DISTRIBUTION`; store code
   uses `APP_STORE`. Preserve product hooks such as saving before update
   relaunch. Use the existing runtime updater/shared package where appropriate;
   these tools do not replace its behavior.
4. Add only actual store capabilities to the store entitlements. The template
   grants only the sandbox, **not** file access, networking, App Groups or
   temporary exceptions. An app needing those capabilities must implement and
   verify its real authorization path. Sandboxed direct distribution is also
   possible, but needs Sparkle's sandbox setup; this example does not enable it.
5. Copy the small config/export-option examples into the consumer, configure
   both export-option `teamID`s, signing identities/profiles and target team,
   then generate the project with `xcodegen generate`. Generated plists and the
   Xcode project must match committed inputs before building. Keep keys in the
   Keychain / established Apple credential store, not in JSON or scripts.
6. Decide bundle-ID and data-migration policy explicitly. Same ID is **not** a
   promise of shared data or safe coexistence. Never overwrite an installed app
   while testing this sample.

## Plan and build

From the consumer repository, after configuring the above:

```bash
macos-distribution plan --config distribution.json --out build/distribution/run-001
macos-distribution build --config distribution.json --out build/distribution/run-001 --dry-run
macos-distribution build --config distribution.json --out build/distribution/run-001
```

`--channel direct`, `--channel app-store`, or the default `all` selects the
channel. Config paths resolve relative to the config file, not the current
working directory; `--out` resolves relative to the caller. Config-owned paths
cannot escape the config directory. Use a Git-ignored output directory.

A plan/dry run reads local config/plists only: no output directory, Xcode
process, keychain operation or network call. `build` requires a clean committed
checkout, archives arm64 + x86_64 separately for each channel, exports locally,
checks source/option drift and refuses existing output directories. It never
stashes, deletes source or retries an uncertain operation. Failures stop the
batch; the receipt identifies the active channel/phase and already-exported
channels. Inspect retained output and select a **new** output directory for a
new run, rather than deleting another run's files.

Output includes per-channel `.xcarchive`, `.xcresult`, `archive.log`,
`export.log`, export directory and a durable `receipt.json`. Complete compiler
and export diagnostics remain in the logs; inspect warnings as well as errors.
`exported_not_published` means exactly that, not release acceptance. Interrupted
runs retain their artifacts and receipt; automatic resume is not implemented.
Project build phases are trusted inputs: review custom scripts for additional
side effects before running any Xcode build. This helper cannot sandbox scripts
inside an arbitrary supplied project.

The store export can be an installer `.pkg`, not a directly runnable `.app`.
The helper audits its **signed archive** and any exported `.app`, but does not
unpack/revalidate exported store packages. `requires_store_validation: true`
remains set. Use Xcode/App Store Connect validation and TestFlight/store-path
acceptance before calling that release ready. The tool passes no
`-allowProvisioningUpdates`; provision signing credentials/profiles separately.

Direct exports still need the product's existing notarization, staple, signed
DMG/update ZIP, appcast and publication pipeline. Store exports need store
validation/upload/review. This helper does **not** upload, publish, notarize,
install, alter account records or migrate data. Export options with
`destination: upload` or the wrong channel method are refused before writes.

## Audit an app

```bash
macos-distribution audit --app /path/to/App.app --channel app-store --bundle-id com.example.App
macos-distribution audit --app /path/to/Development.app --channel app-store --bundle-id com.example.App --stage development
```

Release is the default: verify actual bundle signature, all nested Mach-O
signatures, universal main executable, no debug entitlement, and channel signing
policy. Store artifacts must have the signed sandbox entitlement and no embedded
Sparkle, Sparkle load dependency or `SU*` updater configuration. Direct artifacts
must contain and link Sparkle; this template is intentionally Sparkle-specific.
An app using a different direct updater needs a separately adopted audit policy.

`--stage development` explicitly relaxes distribution-signing/universal/debug
checks so local builds can test channel separation. It is not a workaround for a
failing release. Results always identify stage and unverified functional,
notarization and store-acceptance scope. No audit result alone proves user-file
access, working auto-update, data migration or successful store review.

## CLI contract and tests

No prompts. Human terminals receive readable output; `--json` or non-TTY
stdin/stdout produces `{ok,data,error,meta}` on stdout. Progress goes to stderr.
`--json` is a global option, placed **before** the subcommand. Stable exits:
0 success, 1 execution/audit failure, 2 usage/config error, 3 missing path,
4 permission error, 5 existing output/dirty or changed source. No custom auth
flow exists: native signing/export failures retain native diagnostics.

```bash
python3 -m unittest discover -s tools/macos-distribution -p 'test_*.py' -v
ruff check tools/macos-distribution
```

Tests use disposable fixtures, never user applications or credentials. They
cover both channels, dry-run, error envelopes, option/path validation,
source/option drift, preserved failed output and channel-policy failures.
Native compilation/signing coverage and its limits are recorded separately;
mocked subprocess tests never establish successful Apple export or review.
