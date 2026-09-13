# Contributing to Duolet

Small, focused contributions are welcome. Explain the behavior you want to change
in an issue or pull request, and include before/after screenshots for visual work.

Use macOS with Xcode 26 or newer, then run:

```sh
bash scripts/test.sh
bash scripts/build.sh
```

The app and WidgetKit extension share `Sources/Shared/IndicatorView.swift` and
`DeviceStatus.swift`. Keep both surfaces consistent. Test Wi-Fi, Ethernet,
disconnected, zero battery, and Macs without a built-in battery. Preserve system
appearance and accessibility support. Do not add analytics or network services.

For runtime verification, quit any running copy of Duolet first:

```sh
open build/Build/Products/Release/Duolet.app --args --smoke-test /tmp/duolet-smoke.json
```

Inspect the JSON report for the status item, desktop panel, embedded extension,
and standard/Option-right-click menus. It exercises and restores percentage,
visibility, and size settings. Login registration is opt-in and is not
toggled by this check. Widget gallery availability must also be checked on macOS;
compiling the extension alone does not prove that it appears there.

By contributing, you agree to license your contribution under the MIT license.

To reproduce the isolated README UI snapshots, quit Duolet, then run:

```sh
open build/Build/Products/Release/Duolet.app --args \
  --smoke-test /tmp/duolet-smoke.json --show-menu --capture-ui "$PWD/docs/images"
```

The menu closes automatically after capture. Snapshots use opaque surfaces in
place of backdrop glass and never capture other apps or desktop content.
