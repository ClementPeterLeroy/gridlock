"""Bundled artwork, fonts, and per-player victory sticker caching."""

import logging
from pathlib import Path
import pygame

ROOT = Path(__file__).resolve().parent / "content"
log = logging.getLogger(__name__)


def fit_image(image, bounds):
    rect = image.get_rect().fit(pygame.Rect(0, 0, *bounds))
    return pygame.transform.smoothscale(image, rect.size)


class IdentityAssets:
    def __init__(self, root=ROOT):
        self.root = Path(root)
        self._fonts = {}
        self._stickers = {}
        self.logo = self.image("gridlock_logo.png")
        self.icon = self.image("gridlock_icon.png")
        self.templates = [self.image(f"{name}_victory.png")
                          for name in ("sapphire", "crimson", "emerald", "violet")]
        self.fonts = (self.font("display", 32), self.font("interface", 18),
                      self.font("interface", 15))

    def image(self, filename):
        path = self.root / "px" / filename
        try:
            return pygame.image.load(str(path)).convert_alpha()
        except (OSError, pygame.error) as error:
            log.warning("Gridlock asset unavailable: %s (%s)", path, error)
            return None

    def font(self, style, size):
        key = style, size
        if key not in self._fonts:
            filename = "Cinzel.ttf" if style == "display" else "Lato-Regular.ttf"
            path = self.root / "fonts" / filename
            try:
                font = pygame.font.Font(str(path), size)
                if style == "display":
                    font.set_bold(True)
            except (OSError, pygame.error) as error:
                log.warning("Gridlock font unavailable: %s; using Pygame fallback (%s)", path, error)
                font = pygame.font.Font(None, size)
            self._fonts[key] = font
        return self._fonts[key]

    def banner_text(self, text, bounds=(196, 29)):
        size = 24
        while size > 8:
            font = self.font("display", size)
            if font.size(text)[0] <= bounds[0] and font.get_height() <= bounds[1]:
                break
            size -= 1
        label = self.font("display", size).render(text, True, (255, 250, 231))
        if label.get_width() > bounds[0] or label.get_height() > bounds[1]:
            label = fit_image(label, bounds)
        return label

    def stickers_for(self, game):
        """Generate only changed identities; replay reuses the same surfaces."""
        stickers = {}
        for player in range(game.player_count):
            text = f"{game.display_name(player).upper()} WINS!"
            key = player, text
            if key not in self._stickers:
                template = self.templates[player]
                surface = (pygame.transform.smoothscale(template, (540, 312))
                           if template is not None else pygame.Surface((540, 312), pygame.SRCALPHA))
                if template is None:
                    pygame.draw.rect(surface, (92, 31, 37), (166, 250, 208, 42), border_radius=12)
                label = self.banner_text(text)
                surface.blit(label, label.get_rect(center=(270, 271)))
                # Keep only the latest name for each seat; old matches need no cache entry.
                for old_key in list(self._stickers):
                    if old_key[0] == player and old_key != key:
                        del self._stickers[old_key]
                self._stickers[key] = surface
            stickers[player] = self._stickers[key]
        return stickers
