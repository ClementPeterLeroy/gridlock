"""Optional mixer audio; a missing device or asset should not stop a match."""

from pathlib import Path
import pygame


def load_audio(music_enabled=True):
    sounds = {}
    folder = Path(__file__).resolve().parent / "content" / "sound"
    try:
        if not pygame.mixer.get_init():
            pygame.mixer.init()
    except pygame.error:
        return sounds
    for name, pattern in (("move", "simple_move.wav"),
                          ("victory", "electronic_victory_sound.*")):
        path = next(iter(sorted(folder.glob(pattern))), None)
        if path:
            try:
                sounds[name] = pygame.mixer.Sound(str(path))
                sounds[name].set_volume(0.5)
            except pygame.error:
                pass
    try:
        pygame.mixer.music.load(str(folder / "simple_happy_loop.mp3"))
        pygame.mixer.music.set_volume(0.2)
        if music_enabled:
            pygame.mixer.music.play(-1)
    except pygame.error:
        pass
    return sounds


def set_music(enabled):
    if pygame.mixer.get_init():
        try:
            if enabled:
                if pygame.mixer.music.get_pos() < 0:
                    pygame.mixer.music.play(-1)
                else:
                    pygame.mixer.music.unpause()
            else:
                pygame.mixer.music.pause()
        except pygame.error:
            pass


def play_sound(sounds, name, enabled):
    if enabled and name in sounds:
        sounds[name].play()
