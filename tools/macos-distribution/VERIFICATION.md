# Distribution-toolkit verification

Checked 2026-10-30 on macOS 27.2 / Xcode 27.2 (27B5028f), XcodeGen 2.46.0,
Apple Silicon. This covers the toolkit and its non-UI fixture, **not** a
NeatEditor store migration. The example pins Sparkle 2.9.5 to the repository's
existing tested dependency; it is not a claim about the latest Sparkle release.

Already-aligned mechanical verification did not require additional external
research; the new category diagnostic was checked against Apple's reference,
and retained diagnostics are individually assessed below.

## Automated contracts

```bash
ruff check tools/macos-distribution
python3 -m unittest discover -s tools/macos-distribution -p 'test_*.py' -v
python3.14 -m unittest discover -s tools/macos-distribution -p 'test_*.py' -v
uv run --python 3.11 --no-project python -m unittest discover -s tools/macos-distribution -p 'test_*.py' -v
```

Ruff passed. All 25 tests passed on Python 3.11.14, 3.14 and 3.15.2. They cover
read-only planning, both channels, invalid config/method/upload destination,
path and symlink escape, injection-shaped scheme values, placeholder teams,
structured success/errors (including measured 2/3/4/5 exit paths), dirty/changed
source, changed export options, output preservation, complete failed-build logs,
store resource/link/entitlement rejection and explicit store-validation limits.
The framework's own install-name reference does not count as app linkage.
Mocked signature/command tests establish contract behavior, not Apple acceptance.

Logs: `build/distribution-toolkit/ruff.log`, `tests-python3.log`,
`tests-python3.14.log`, `tests-python311.log`.

## Native compilation and returned values

The following command was run with a clean action for each combination of
`DistributionExample` / `DistributionExample-AppStore` and Debug / Release:

```bash
xcodebuild -project DistributionExample.xcodeproj -scheme "$scheme" \
  -configuration "$config" -destination 'generic/platform=macOS' \
  -derivedDataPath "$separate_channel_directory" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  OTHER_CODE_SIGN_FLAGS= ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  clean build analyze
```

All four builds and analyses passed, compiling the probe for both architectures.
Ad-hoc identity overrides are deliberate **development fixture** settings, never
production export settings. The tool's development audit passed on all four
actual apps. Readback after the final template correction:

| Readback | Direct | App Store |
|---|---|---|
| Version / build | 1.0.0 / 1 | 1.0.0 / 1 |
| Main architectures | arm64 + x86_64 | arm64 + x86_64 |
| Signed sandbox entitlement | false | true |
| Embedded Sparkle | present | absent |
| App-side Sparkle load command | present (Debug dylib / Release main) | absent |

Running the actual direct Debug and sandboxed store Release probe executables
returned exit 0 and respectively:

```text
channel=direct updater=SPUStandardUpdaterController
channel=app-store updater=App Store
```

The probe only references the Sparkle type; it does not start an updater or
contact an example feed. Complete logs, audit JSON and returned text are in
`build/distribution-toolkit/{direct,store}-{Debug,Release}*` and
`{direct,store}-runtime.txt`. The case-insensitive filesystem retains the
original `direct-debug.log` spelling for that log.

## Real Developer ID archive and export

A disposable copy of the sample was configured with the installed Developer ID
team, generated, package-resolved and committed before using the actual helper:

```bash
python3 tools/macos-distribution/distribution.py build \
  --config "$fixture/example/distribution.json" \
  --out build/distribution-toolkit/signed-direct-run2 --channel direct
```

The real archive and `-exportArchive` both passed. The helper returned
`exported_not_published`; its release audit checked all six Mach-O binaries in
the exported app for Developer ID signing, timestamp/runtime and absence of
`get-task-allow`, plus root bundle validity, universal main and channel policy.
Running that **exported** app executable returned the direct-channel line above.
This verifies the helper's real write path, not just its planned argv.

Fixture source commit: `ce4e560ad2fdcdeec883712bea8bf19159f02735` (temporary test
repository, not an application release tag). The temporary fixture was removed
by the test harness; export artifacts and full logs remain under the stated
build directory. Tool SHA256 recorded in the receipt:
`1f9f1ad2cc2da82180ee7c4ef1d8cd80fc974da2ac3f1997d4ca23c51398ffc5`.
The tracked toolkit source can be hashed to check the same implementation.

Evidence: `signed-direct-run2/receipt.json`, `direct/archive.log`,
`direct/archive.xcresult`, `direct/export.log`, `native-export-stdout.json`,
`native-export-stderr.log` and `exported-probe-runtime.txt`, all beneath
`build/distribution-toolkit/` (the `direct/` entries are under the signed run).
These are local test artifacts, not public downloads or notarized installers.

## Diagnostics

- **Fixed: no application category.** The first real archive warned that no app
  category was set. The common template now requires product-supplied
  `app_category`, and the probe supplies the developer-tools category. A fresh
  full four-configuration build/analyze and a fresh signed archive/export no
  longer report it. No diagnostic was disabled.
- **Retained: AppIntents metadata extraction skipped.** Xcode's
  `appintentsmetadataprocessor` reports `Metadata extraction skipped, no
  AppIntents.framework dependency found` once per app build/archive. Origin:
  Xcode's metadata step. Evidence: the fixture imports only Foundation and,
  in the direct build, Sparkle; it declares no App Intents feature. Reason:
  there is no fixture metadata to extract. Residual risk: this says nothing
  about future apps that declare App Intents. Follow-up: such consumers must
  supply and verify their actual App Intents dependency/metadata; do not reuse
  this fixture-specific assessment to ignore a product warning. The notice is
  kept visible in complete logs, with no suppression or dummy dependency.

No other compiler or static-analysis diagnostic remained in the final four
build/analyze logs or final archive/export logs.

## Limits

- No Mac App Store distribution signing identity was available. Store release
  signing/export, exported `.pkg` validation, TestFlight and store review were
  **not** verified. An ad-hoc sandboxed build is not a store release.
- No notarization, Gatekeeper acceptance, DMG/appcast publication or actual
  update installation was performed for this developer fixture.
- Intel code compiled, but was not executed on Intel; the macOS 13 deployment
  target was not runtime-tested. Runtime evidence is native arm64 on macOS 27.2.
- No NeatEditor source, menus, preferences, document storage or installed editor
  was changed. Sandboxed document reopen/save/autosave/restore and migration
  acceptance remain product adoption work, not toolkit passes.
- CLI behavior was exercised directly. Independent fresh-agent usability was
  not evaluated because no external worker/runtime was authorized.
