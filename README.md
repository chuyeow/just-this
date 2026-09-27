# Just This

A tiny pill that floats above every window, on every Space, showing your one current focus.

- **Edit**: double-click the pill (or menu bar icon › Edit Focus…). Return saves, Esc cancels.
- **Out of the way**: move the cursor near it and it slides aside so you can reach what's underneath. It comes back when the cursor leaves.
- **Hold ⌥** to stop it dodging, so you can double-click or drag it. Drag drops it at a new home; menu bar › Reset Position puts it back at top centre.
- Lives in the menu bar only (no Dock icon). Quit from the menu bar icon.

## Build

```sh
swift test                      # dodge logic + editing
scripts/build-app.sh            # -> build/Just This.app (universal, ad-hoc signed)
scripts/build-app.sh --install  # also copies to /Applications
```

Icon: `Resources/AppIcon.png`, generated with `gpt-image-2.5-sunburst`.
