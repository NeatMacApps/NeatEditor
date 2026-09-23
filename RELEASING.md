# Releasing NeatEditor

This repository uses a tag-driven GitHub Actions workflow to build and publish release assets.

## What Happens On Release

When you push a tag like `v1.0.0`, GitHub Actions will:

- select Xcode 16.2
- generate the Xcode project with XcodeGen
- build a Release configuration macOS app
- package `NeatEditor.app` as a universal zip
- build a drag-install dmg holding `NeatEditor.app` plus an `Applications` symlink
- generate `SHA256SUMS.txt` covering both the zip and the dmg
- create or update the matching GitHub Release (zip first, dmg uploaded
  separately, then the asset list is read back to confirm all three files
  are present)

## Release Asset Names

The generated asset name follows this pattern:

```text
NeatEditor-v1.0.0-macOS-universal.zip
NeatEditor-v1.0.0-macOS-universal.dmg
```

The dmg is the first-install package: open it and drag `NeatEditor.app` onto
`Applications`. The zip remains for scripted installs and updates.

## Publish A Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

After the workflow finishes, open the repository's Releases page to verify:

- the release exists for the tag
- the zip asset was uploaded
- the dmg asset was uploaded
- the checksum file was uploaded

## Important Notes

- CI builds an **unsigned** app and uploads unsigned placeholders. Public
  assets must be replaced with Developer ID-signed + notarized builds:
  on the maintainer Mac (which holds the Developer ID certificate and the
  App Store Connect API key) build Release, re-sign nested Sparkle helpers
  inside-out (`Downloader.xpc`, `Installer.xpc`, `Updater.app`,
  `Autoupdate`, framework, then the app — `xcodebuild build` does not
  re-sign SPM-provided nested binaries and notarization will reject them),
  notarize the app-zip and the dmg separately, staple both, verify with
  `spctl -a -t install` (expect `Notarized Developer ID`), then replace the
  release assets one file at a time and re-verify with anonymous downloads.
- Until CI gains signing secrets, every tag release needs this local
  sign-and-replace pass; an unsigned `Latest` will be blocked by Gatekeeper
  (“Apple could not verify … is free of malware”).

## Versioning

- The tag name without the leading `v` becomes `MARKETING_VERSION`.
- `CURRENT_PROJECT_VERSION` is set from the GitHub Actions run number.

## Re-running A Failed Release

If the tag already exists, fix the workflow or repository state first, then re-run the workflow from GitHub Actions.
