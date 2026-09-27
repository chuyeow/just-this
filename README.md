# Just This

A tiny pill that floats above every window, on every Space, showing your one current focus.

- **Edit**: double-click the pill, click the Dock icon, or Edit › Edit Focus… (⌘E). Return saves, Esc cancels.
- **Out of the way**: move the cursor near it and it slides aside so you can reach what's underneath. It comes back when the cursor leaves.
- **Hold ⌥** to stop it dodging, so you can double-click, drag or right-click it. Keep reaching without ⌥ and it tells you: "Hold ⌥ Option key to reach".
- **Rest anywhere**: ⌥-drag it to any spot on any display; it stays there across launches and is pulled back on-screen if a display goes away.
- **Breathes**: the whole pill swells and brightens slowly, the dot's glow blooming with it (~10 breaths a minute). Off in Settings, and automatically under Reduce Motion.
- **Themes**: Dawn (default, apricot-to-lilac gradient), Paper, Ember, Ocean, Forest, Gold (black and gold). Every theme is tested for readable contrast (WCAG 4.5:1 text, 3:1 dot).
- **Settings** (⌘, after clicking the pill or while the app is in front; or Dock/right-click › Settings…): theme, breathing, slide-away on/off and distance, the hint on/off, text size, opacity, reset position, open at login.
- Lives in the Dock. Right-click the Dock icon for Edit Focus / Settings; ⌘Q quits.

## Build

```sh
swift test                      # dodge, hint, placement, themes, editing, settings, Dock
scripts/build-app.sh            # -> build/Just This.app (universal, ad-hoc signed)
scripts/build-app.sh --install  # also copies to /Applications
```

Icon: `Resources/AppIcon.png`, generated with `gpt-image-2.5-sunburst`.

## Releases

Every merge to `main` runs the tests, builds a universal `.dmg` and publishes it as a GitHub release (`v1.0.<run>`). PRs run the tests.

The app is ad-hoc signed, not notarized. After installing from a downloaded `.dmg`, right-click the app › Open once, or:

```sh
xattr -dr com.apple.quarantine "/Applications/Just This.app"
```
