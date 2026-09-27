# VinylPod

A floating now-playing panel for Omarchy/Quickshell. The click wheel is a
turntable: it spins for real while a track plays, the album art sits on the
label, and prev/play-pause/next fade in over the record itself on hover.

## Files
- `manifest.json` — plugin manifest (id `maiosx.vinylpod`, kind `overlay`)
- `VinylPod.qml` — the panel: layout, MPRIS binding, transport, hover controls
- `Model.js` — copied unchanged from `spotmarchy-main`: MPRIS matching
  (`findSpotify`), time formatting, and the album-art probe pipeline
  (`artProbeTarget` / `artProbeScript` / `parseArtProbe`, which shells out to
  ImageMagick + curl). Nothing in this file was modified.

## What's live vs. static
Everything under "player" in `VinylPod.qml` — title, artist, art, progress,
play state — reads from `Quickshell.Services.Mpris`, exactly the same
properties Spotmarchy's `Panel.qml` reads (`trackTitle`, `trackArtist`,
`trackArtUrl`, `position`/`length`, `isPlaying`). There's no polling or
placeholder data; if no Spotify MPRIS player is found, `live` is false and
the panel shows "Nothing playing" (or hides entirely, depending on
`showWhenClosed`).

## Two things I did not guess at
1. **Settings binding.** The manifest declares `corner`, `margin`, and
   `showWhenClosed` as user-configurable, but the uploaded template only
   shows how a *bar widget* reads settings (`setting("key", default)`,
   defined on the `Panel` base component from `qs.Ui`, which isn't part of
   this template). Rather than invent that call and risk it being wrong,
   `VinylPod.qml` declares those three as plain properties hardcoded to the
   manifest's defaults (bottom-right, 24px margin, hidden when idle). Swap
   in the real settings call once you point me to (or paste) the base
   overlay/panel component this plugin should extend.
2. **Rounded album art.** Spotmarchy's panel uses `QtQuick.Effects` +
   `MultiEffect` masking for its art thumbnail. I used a simpler
   `Rectangle { radius; clip: true }` around the `Image` instead — same
   visual result for a plain crop, fewer moving parts to get wrong. If you
   want the exact masking technique back (e.g. for a non-circular shape
   later), it's a straightforward swap.

## Not carried over from Spotmarchy
`Panel.qml`'s bar-widget chrome (the bar glyph, marquee label, scroll-to-skip,
shuffle/repeat/volume row, IPC handler) isn't in here — this is a standalone
floating panel, not a bar entry, so only the MPRIS/model plumbing and the
now-playing data were reused, per the brief.
