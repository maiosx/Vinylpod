# VinylPod

A floating now-playing panel for Omarchy (Quattro shell / Quickshell). The
click wheel is a turntable: it spins for real while a track plays, the album
art sits on the label, and prev/play-pause/next fade in over the record
itself on hover.

## Install

```bash
omarchy plugin add https://github.com/maiosx/vinylpod.git
```

This clones the repo into `~/.config/omarchy/plugins/maiosx.vinylpod/` and
lands it **disabled** so you can review the code first. Enable it with:

```bash
omarchy plugin enable maiosx.vinylpod
```

(or **Setup › Plugins** in the GUI). Update later with
`omarchy plugin update maiosx.vinylpod`, remove with
`omarchy plugin remove maiosx.vinylpod`.

### Keybinding

Add a shortcut to toggle the panel visible/hidden. In
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + M", "VinylPod", "omarchy-shell shell toggle maiosx.vinylpod '{}'")
```

Same `toggle <id> <payloadJson>` IPC call the stock config uses for the
Omarchy menu (`omarchy-shell shell toggle omarchy.menu '{"menu":"root"}'`).
Check `omarchy menu keybindings --print` first in case Super+M is already
taken by a default binding — if so, either pick another combo or
`hl.unbind("SUPER + M")` immediately above the `o.bind(...)` line to
override it. The file reloads live on save, no restart needed.

## Files
- `manifest.json` — kind `panel` (Quattro's kind for a persistent/summoned
  floating window, e.g. an OSD — not `overlay`, which is fullscreen), id
  `maiosx.vinylpod`, entry point `VinylPod.qml`
- `VinylPod.qml` — extends `Panel` from `qs.Ui` (the same base class
  Spotmarchy's own popout extends), for `open()`/`close()`/`toggle()`, the
  `setting(key, default)` accessor, and IPC. Theming reads from the
  `qs.Commons` `Color`/`Style` singletons rather than hardcoded hex, so it
  follows whatever theme is active.
- `Model.js` — copied unchanged from `spotmarchy-main`: MPRIS matching
  (`findSpotify`), time formatting, and the album-art probe pipeline
  (shells out to ImageMagick + curl). Nothing in this file was modified.

## What's live vs. static
Title, artist, art, progress, and play state all read from
`Quickshell.Services.Mpris` — the same properties Spotmarchy's `Panel.qml`
reads (`trackTitle`, `trackArtist`, `trackArtUrl`, `position`/`length`,
`isPlaying`). No polling, no placeholder data. If no Spotify MPRIS player is
found, `live` is false and the panel shows "Nothing playing" (or hides
entirely, depending on the `showWhenClosed` setting).

## One thing I couldn't verify
Corner/margin anchoring for a **standalone** panel summon (no invoking bar
widget) isn't shown anywhere in the Spotmarchy template — it only shows
`Panel` anchoring *relative to a bar widget's own slot*. The `anchors` /
`margins` blocks in `VinylPod.qml` use Quickshell's own `PanelWindow`
convention as a best guess for how `Panel` forwards screen-corner placement;
confirm against `qs/Ui/Panel.qml` in your Omarchy checkout (the shell docs
point at `shell/services/PluginRegistry.qml` for the authoritative schema)
before relying on it.

## Not carried over from Spotmarchy
Spotmarchy's bar-widget chrome (the bar glyph, marquee label, scroll-to-skip,
shuffle/repeat/volume row) isn't in here — this is a standalone floating
panel, not a bar entry, so only the MPRIS/model plumbing and now-playing
data were reused.
