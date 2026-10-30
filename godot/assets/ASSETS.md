# Reused Classic assets

The alpha.2.3 UI and audio use byte-for-byte copies of existing repository assets.
They are stored inside the Godot project so imports and future exports do not
depend on files outside `res://`. No Pygame source asset was changed.

| Godot path | Original source | Use |
| --- | --- | --- |
| `audio/simple_move.wav` | `pygame/content/sound/simple_move.wav` | Pawn movement; pitched down for wall placement |
| `audio/simple_happy_loop.mp3` | `pygame/content/sound/simple_happy_loop.mp3` | Quiet looping background music |
| `audio/electronic_victory_sound.mp3` | `pygame/content/sound/electronic_victory_sound.mp3` | Match-end sound |
| `victory/*_victory.png` | Matching sapphire/crimson/emerald/violet files in `pygame/content/px/` | Existing transparent trophy/foam-hand/banner artwork |
| `fonts/Cinzel.ttf` | `pygame/content/fonts/Cinzel.ttf` | Dynamic uppercase victory banner |
| `fonts/Cinzel-OFL.txt` | `pygame/content/fonts/Cinzel-OFL.txt` | Unmodified SIL Open Font License and copyright notice |

The trophy retains its embedded WINNER plaque. The empty banner receives a single
runtime player-name announcement; no generated artwork is written to disk.
The original models and their materials remain in `models/` unchanged.

Audio remains development placeholder material. The wall sound reuses the move
recording at a lower pitch; it is not a final bespoke wall-placement sound.

## Beta.1 branding and interface font

- `branding/gridlock_logo.png`: the original PNG payload extracted without pixel
  changes from `pygame/content/px/gridlock_logo_transparent.svg`. Its alpha channel
  is preserved; this is the official repository logo, not newly generated artwork.
- `fonts/Lato-Regular.ttf` and `fonts/Lato-OFL.txt`: unmodified copies from
  `pygame/content/fonts/`, used for readable menu and HUD text under their included
  SIL Open Font License. Cinzel and all existing victory artwork remain unchanged.

Original Classic assets remain untouched. No new external dependency was added.

## Beta.2 startup and application icon

- `branding/gridlock_intro.ogv` converts the existing 960 x 540, 20 fps, 5.8-second
  `pygame/content/px/gridlock_startup_storyboard.mp4` to Ogg Theora (`libtheora`,
  quality 8, no audio). This preserves the official storyboard and uses Godot's
  built-in decoder. No FFmpeg/Python runtime dependency ships with the game.
- `branding/gridlock_icon.png` is an unmodified copy of the official Classic icon.
  `gridlock_icon.ico` contains standard 16/32/48/64/128/256 pixel sizes converted
  from that artwork for Windows resource branding. No replacement logo was drawn.

Reproduce the development conversion with FFmpeg:

```powershell
ffmpeg -i pygame/content/px/gridlock_startup_storyboard.mp4 -an -c:v libtheora -q:v 8 godot/assets/branding/gridlock_intro.ogv
```

The Windows export helper packages the complete engine notices from the installed
Godot build and the unchanged font licenses. No blanket game license is added.
