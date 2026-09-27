# Just This

A tiny pill that floats above every window, on every Space, showing your one current focus.

- **Edit**: double-click the pill (or menu bar icon › Edit Focus…). Return saves, Esc cancels.
- **Out of the way**: move the cursor near it and it slides aside so you can reach what's underneath. It comes back when the cursor leaves.
- **Hold ⌥** to stop it dodging, so you can double-click, drag or right-click it. Keep reaching without ⌥ and it tells you: "Hold ⌥ Option key to reach".
- **Rest anywhere**: ⌥-drag it to any spot on any display; it stays there across launches and is pulled back on-screen if a display goes away.
- **Settings** (menu bar or right-click › Settings…, ⌘,): slide-away on/off and distance, the hint on/off, text size, opacity, reset position, open at login.
- Lives in the menu bar only (no Dock icon). Quit from the menu bar icon.

## Build

```sh
swift test                      # dodge, hint, placement, editing, settings
scripts/build-app.sh            # -> build/Just This.app (universal, ad-hoc signed)
scripts/build-app.sh --install  # also copies to /Applications
```

Icon: `Resources/AppIcon.png`, generated with `gpt-image-2.5-sunburst`.
