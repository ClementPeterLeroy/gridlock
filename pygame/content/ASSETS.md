# Gridlock identity assets

The menu now uses the supplied `px/gridlock_logo_transparent.svg`. This SVG
wraps a transparent PNG; `identity.py` decodes that embedded image directly
because SDL_image's SVG renderer omits embedded raster artwork. Transparency,
original proportions, and artwork are preserved without a new dependency.

The supplied `px/gridlock_startup_storyboard.mp4` contains the official logo
in its final frame. No separate official logo or icon file was present when
v2.7 was implemented. `gridlock_logo.png` is a proportional crop of that
frame; `gridlock_icon.png` arranges its existing lock and gemstone details
over a dark grid with a white outer border. No replacement artwork was
generated. That older opaque logo PNG is retained as a legacy export and is
no longer used by the menu. The application icon is loaded independently.

The supplied video is 960 x 540, 20 fps, and 116 frames (5.8 seconds).
Playback displays every frame and letterboxes proportionally. It is
video-only; game music starts after it finishes. Window close remains active;
returning to the menu does not replay it. Missing or undecodable media logs
a warning and allows the game to continue.

## Victory templates

`sapphire_victory.svg`, `crimson_victory.svg`, `emerald_victory.svg`, and
`violet_victory.svg` retain the supplied trophy, foam hands, colors, and
banner. The trophy retains its original `WINNER` plaque; the banner has no
fixed player text, so custom names can be rendered at runtime. Transparent 900 x 520
PNG exports are bundled for runtime use; no SVG renderer is needed to play.
Legacy blue/red/green files are retained as source artwork and are not loaded
by the new identity layer.

`identity.py` scales each template to 540 x 312, renders uppercase personalized
text in the banner, and caches it by player index and displayed name. It
keeps at most one current name per seat. Restarting with unchanged names
reuses surfaces; changes replace only the affected entries. Rendering does
not write generated stickers to disk.

To reproduce the SVG/PNG/logo/icon exports during development:

```powershell
python -m pip install pillow resvg-py imageio-ffmpeg
python tools/prepare_identity.py
# Regenerate stickers alone, preserving the current logo and replacement icon:
python tools/prepare_identity.py --stickers-only
```

Pillow and resvg-py are development tools, not runtime requirements. Cropping
coordinates target the supplied storyboard; review them if replacing the video.

## Fonts

- [Cinzel](https://github.com/google/fonts/tree/main/ofl/cinzel): display
  headings and victory text. Copyright 2020 The Cinzel Project Authors.
- [Lato](https://github.com/google/fonts/tree/main/ofl/lato): interface
  text. Copyright 2010–2014 tyPoland Lukasz Dziedzic.

Both are bundled unmodified under the SIL Open Font License 1.1. The complete
licenses and copyright notices are in `fonts/Cinzel-OFL.txt` and
`fonts/Lato-OFL.txt`. Font objects are cached by style and size. Missing fonts
produce a warning and fall back to Pygame's built-in font. Character coverage
depends on the selected font; arbitrary Unicode names may contain missing glyphs.

## Video dependency

[`imageio-ffmpeg`](https://github.com/imageio/imageio-ffmpeg) is the only new
runtime dependency. Its FFmpeg executable decodes RGB frames on a worker
thread; a bounded three-frame queue prevents loading the entire movie into
memory. Pygame handles display and events on the main thread. Decoder cleanup
closes the frame generator and joins the worker on completion or window close.

Existing sound files remain development placeholders.
