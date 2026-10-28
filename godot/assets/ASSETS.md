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
