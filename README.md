# VinylPod

A now-playing panel for Omarchy (Quattro shell / Quickshell). The letter **V**
on the bar opens it. The click wheel is a turntable: it spins while a track
plays, the album art sits on the label, and prev/play-pause/next fade in over
the record on hover.

## Install

```bash
omarchy plugin add https://github.com/maiosx/Vinylpod.git
omarchy plugin enable maiosx.vinylpod
omarchy bar move maiosx.vinylpod --section right
```

(or **Setup › Plugins**, then drag **V** onto the bar).

### Why V used to do nothing

The first bar chip shelled out to `omarchy-shell toggle` and the panel bound
`visible` to “Spotify is already playing”. With no player, toggle succeeded
and still painted nothing. The V chip now **loads `VinylPod.qml` itself**
(the same `Loader` + `KeyboardPanel` contract as clock/weather) and always
shows the panel when you click — “Nothing playing” if Spotify isn’t live.

| Click | Action |
| --- | --- |
| Left on **V** | Open / close the panel |
| Right on **V** | Play / pause |
| Middle on **V** | Next track |
| Hover the wheel | Prev / play-pause / next |

### Keybinding

In `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + M", "VinylPod", "omarchy-shell maiosx.vinylpod toggle")
```

Same IPC target as the bar widget (`open` / `close` / `toggle` / `playPause` /
`next` / `previous`). Check `omarchy menu keybindings --print` first in case
Super+M is taken — `hl.unbind("SUPER + M")` above the bind to override.

## Files

- `manifest.json` — kind `bar-widget`, id `maiosx.vinylpod`
- `BarWidget.qml` — letter **V**; loads the panel; owns IPC
- `VinylPod.qml` — `Panel` + `KeyboardPanel` popout (MPRIS + click wheel)
- `Model.js` — Spotmarchy MPRIS matching + art-probe pipeline (unchanged)

## Live data

Title, artist, art, progress, and play state read from
`Quickshell.Services.Mpris`. No polling. If no Spotify player is found the
panel still opens and shows “Nothing playing”.
