# Dual-channel macOS distribution

Research checked on 2026-10-30. These findings support a reusable build-tool
reference; they do not establish NeatEditor's readiness for the Mac App Store.

## Evidence and choices

| Reference | Inspected behavior | Adopted / not copied |
|---|---|---|
| [Apple Review Guidelines 2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility) | (i) requires sandboxing; (vii) requires store-delivered updates for Mac App Store apps. | Distinct store build policy. Sandboxing alone does not prohibit Sparkle in an outside-store app. |
| [CotEditor](https://github.com/coteditor/CotEditor/tree/1bf62cfd6415023f28280f03f7e28349d2328de2) | Shallow checkout inspected: `Configurations/CotEditor*.xcconfig`, `CotEditor.xcodeproj/project.xcproj`, and `UpdaterManager.swift`. It shares app sources, uses separate Sparkle configurations/entitlements, and gates updater integration with a compile condition. | Reuse the separation of shared code, channel configuration and updater integration. Do not copy its editor, settings, UI, project format or complete signing policy. |
| [SwiftLee / RocketSim](https://www.avanderlee.com/xcode/sparkle-distribution-apps-in-and-out-of-the-mac-app-store/) | A documented launch crash followed removing an embedded Sparkle framework without removing the Mach-O load dependency. A single target can work but requires carefully conditional framework linking. | Audit both embedding and actual Mach-O linkage. Do not use post-build framework deletion. |
| [XcodeGen ProjectSpec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md#target-template) | Target templates share settings/sources; target-specific dependencies can remain separate. Included specs support `relativePaths: false`. | Two lightweight targets from shared templates, preserving SwiftPM dependency management without conditional-linking tricks. This is a recommendation for the current XcodeGen/SPM setup, not an industry-wide mandate. |
| [Sparkle documentation](https://sparkle-project.org/documentation/) | Sparkle manages direct-distribution updates and recommends archive/distribution signing. | Keep Sparkle itself and the product's existing signing/notarization/appcast publisher; do not implement another updater or hand-sign nested Sparkle components. |
| Installed `xcodebuild -help` (Xcode 27.2) | Export methods include `developer-id` and `app-store-connect`; `destination` distinguishes local export from upload. | Validate local-only export options before executing. Do not use deprecated `app-store` in new examples. |
| [Apple sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) | User-selected access is process-scoped; explicit security-scoped bookmarks preserve access across launches and require balanced access calls. | Treat file reopening/autosave/restoration as separate product acceptance. No automatic migration or blanket filesystem entitlement. |

## Verified template pitfalls

Native fixture builds established two XcodeGen details that source inspection
alone missed: a configuration-level compilation-condition value replaced the
same target's base value, and an omitted generated Info.plist version defaulted
to `1.0` instead of following `MARKETING_VERSION`. The templates now define each
channel condition in both configurations and explicitly bind both version keys
to build settings. Keep native two-channel/two-configuration coverage when
changing these templates.

The signed archive also exposed a missing-category warning. Applications must
supply their own category via `app_category`; the developer fixture uses
`public.app-category.developer-tools`, an approved value in
[Apple's category reference](https://developer.apple.com/documentation/bundleresources/information-property-list/lsapplicationcategorytype).
This is metadata, not permission to add or redesign any product interface.

## Reusable component boundary

1. `dual-channel.yml`: common target templates with dependency-level updater
   exclusion. Apps supply names, identifiers, sources, capabilities and signing.
2. `distribution.py`: standard-library-only local plan/build/audit helper. A plan
   is read-only. Builds require clean committed source, preserve complete Xcode
   diagnostics, use separate channel output paths, and never replace existing
   outputs. Export options must explicitly request local export.
3. Artifact audit: check bundle identity, channel marker, executable presence,
   Sparkle resources and Mach-O dependencies, signed sandbox entitlement for
   store builds, and release debug entitlement. Passing this narrow audit is
   not Apple validation, notarization, functional acceptance or security review.
4. Product adapters own menus/settings, save-before-relaunch, persistent file
   authorization, entitlements, licensing and store metadata. Existing shared
   `MacKitUpdater` remains the updater-shell authority; this toolkit is not a
   competing runtime updater abstraction.

The toolkit stays callable from any repository using an explicit config path;
there is no need to copy it into each application. It is currently maintained
as a reference in this public repository. A versioned standalone/shared package
should replace this source only when its ownership and a consuming application
are actually established; do not maintain two authoritative copies.

## Identity and data

Using the same bundle ID can support one product identity but does not prove
shared sandbox-container, preferences, Keychain, TCC or purchasing behavior.
Using separate IDs makes coexistence explicit but requires an explicit migration
and entitlement policy. Neither is an automatic universal default. The example
uses one ID and isolated build directories; it must not be installed alongside
an existing same-ID app during verification.

Store builds must omit update controls, not present a disabled/no-op updater as
if it worked. Use an explicit channel compilation condition, not receipt-file
presence or `canImport(Sparkle)` as the distribution policy. A receipt may be
absent from a local development build, while module visibility is not proof of
which channel was requested.

## NeatEditor adoption remains separate

The existing application always depends on Sparkle and uses a product-specific
updater that saves documents before relaunch. Its current release route remains
unchanged. Before enabling a store target, audit external-file reopening,
background autosave, rename/trash, selected storage folders and relaunch restore
under the actual sandbox. Do not quietly redirect existing data, assume saved
path strings grant access, or weaken the sandbox with temporary exceptions.

No store signing identity was installed at inventory time (only Apple
Development and Developer ID Application identities were found). Development
build verification cannot establish successful App Store export/submission.
