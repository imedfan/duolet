# Local release verification — 1.0.0

Verified on macOS 26 with Xcode 26.6, September 13, 2026.

- Universal Release build succeeds for the app and WidgetKit extension; both
  executables contain arm64 and x86_64 slices.
- Seven core tests pass: normalized/clamped and invalid capacity, paused charging,
  external accessory filtering, missing power state, active-route selection,
  and the explicit `wifi.slash` disconnected symbol.
- Live smoke check confirms a visible 22 pt template status image with 1×/2×/3×
  representations, visible desktop widget, embedded extension, no ordinary app
  window, standard menu, network-specific settings menus, and Option-right-click
  routing. Percentage, widget visibility, and all three sizes pass interaction checks.
- Native-menu and live-widget UI snapshots were visually inspected. Backdrop glass
  is replaced with opaque surfaces in these isolated captures; the indicator-state
  artwork uses documented sample data and was also visually inspected.
- PlugInKit reports `org.duolet.Duolet.Widget (1.0.0)` registered on the build Mac.
- DMG checksum verification, read-only mount, Applications symlink, bundled icon,
  and embedded extension checks pass. The app was copied from the mounted DMG to
  a clean test folder, its nested signatures verified, and its diagnostic launched.
  The copied executable matches the one used for the live smoke check.

The prepared installer is ad-hoc signed and not notarized. Developer ID signing,
first-download Gatekeeper behavior, the actual WidgetKit gallery/timeline on a
clean Mac, Intel hardware runtime, and macOS 14–15 runtime have not been verified.
The deployment target and universal build cover those platforms at build time.
Hosted CI results are available in the repository's [Actions tab](https://github.com/imedfan/duolet/actions).
