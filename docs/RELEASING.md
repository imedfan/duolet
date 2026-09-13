# Releasing Duolet

## Prepared release

Version 1.0.0 targets macOS 14+ on arm64 and x86_64. The local DMG is ad-hoc signed
and has not been notarized. Do not describe it as Apple-verified or notarized.
The movable widget and menu bar work without a Developer ID. Check WidgetKit
gallery registration separately on a clean Mac with the intended release signature.

```sh
bash scripts/test.sh
bash scripts/package.sh
hdiutil verify dist/Duolet-1.0.0-universal.dmg
(cd dist && shasum -a 256 -c SHA256SUMS)
```

Mount the DMG, copy Duolet into Applications, eject, and launch the installed app.
Check the menu, percentage, offline glyph, sizes, glass, dragging, login controls,
wake updates, and both desktop/WidgetKit variants. Test downloaded/quarantined
artifacts on a separate Mac; a local launch cannot prove the first-download flow.

## Developer ID and notarization

An Apple Developer Program membership, Developer ID Application certificate, and
notarization credentials are required. Follow [Apple's notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
and [custom workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
Never commit certificates, passwords, API keys, or provisioning profiles.

1. Build with your Developer ID identity and team, signing both targets:

   ```sh
   bash scripts/build.sh ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
     CODE_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
     DEVELOPMENT_TEAM=TEAMID OTHER_CODE_SIGN_FLAGS=--timestamp
   ```

2. Zip the signed app with `ditto -c -k --keepParent`, submit it using
   `xcrun notarytool submit ... --keychain-profile PROFILE --wait`, inspect the
   accepted result, and staple the app with `xcrun stapler staple APP_PATH`.
3. Stage that signed, stapled app and an Applications symlink in a DMG. Do not run
   the default packaging build afterward: rebuilding can discard the stapled ticket.
   Replace the local-signature notice in the disk's Read Me with the actual status.
4. Sign the DMG with your Developer ID, submit the DMG with notarytool, and staple it.
   Validate with `xcrun stapler validate`, `codesign --verify --deep --strict`, and
   `spctl --assess --type execute` on the app. Regenerate `SHA256SUMS` after stapling.

The checked-in app icon can be regenerated with `bash scripts/artwork.sh`; its
source is `Sources/App/ReleaseArtwork.swift`. Run `bash scripts/source-archive.sh`
after packaging to produce a clean source ZIP and checksums for both artifacts.

## Publish on GitHub

The prepared source archive includes sources, project, tests, icon, screenshots,
MIT license, contribution guide, and CI workflow. It excludes build caches and
personal IDE state. The repository is [imedfan/duolet](https://github.com/imedfan/duolet).

Push changes to the repository and wait for the Build Duolet workflow.
Create a version tag and attach
`Duolet-1.0.0-universal.dmg` and `SHA256SUMS` to a GitHub Release. GitHub also
provides source archives for tags. Keep installers in Releases, not Git history.
State the real signing/notarization status in release notes, and update the
README download link for each release.

Suggested release text:

> Duolet combines a live battery/network menu-bar indicator, a movable desktop
> widget, and a bundled WidgetKit extension. macOS 14+, Apple Silicon and Intel.
> Drag the app into Applications to install. This initial community build is
> ad-hoc signed and not notarized; see the README for first-launch instructions
> and WidgetKit registration limitations.
