# Tools

## icon_gen.swift

Draws the app icon programmatically — rounded-rect gradient背景 + the
`battery.100.bolt` SF Symbol, tinted, with a soft top-left highlight and optional
glow. Renders at 1024×1024.

`Assets.xcassets/AppIcon.appiconset/` holds the generated PNGs, so you only need
this when you want to change the icon's look rather than just rebuild the app.

```bash
swiftc -O -framework AppKit -o /tmp/icon_gen Tools/icon_gen.swift
/tmp/icon_gen                    # writes the 1024px PNG(s) next to the CWD
# then downscale into Assets.xcassets/AppIcon.appiconset/ (16…1024)
```

Rescued from the pre-Xcode-project version of this app (`build.sh` + `swiftc`
era), which is otherwise superseded. It was the only file there not represented
in this repository.

## AppIcon.icns

Prebuilt `.icns` from the same era. The Xcode build takes its icon from
`Assets.xcassets`, so this is kept only for hand-rolled `.app` bundles (the
sibling DiskHealthCenter project still assembles bundles that way).
