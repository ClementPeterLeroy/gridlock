"""Unscaled game canvas centered inside a window or native fullscreen display."""

import logging
import pygame
from settings import WINDOW_WIDTH, WINDOW_HEIGHT, BACKGROUND

log = logging.getLogger(__name__)


class GameDisplay:
    def __init__(self):
        self.fullscreen = False
        self.window = pygame.display.set_mode((WINDOW_WIDTH, WINDOW_HEIGHT))
        self.canvas = pygame.Surface((WINDOW_WIDTH, WINDOW_HEIGHT)).convert()

    @property
    def offset(self):
        return ((self.window.get_width() - WINDOW_WIDTH) // 2,
                (self.window.get_height() - WINDOW_HEIGHT) // 2)

    def set_fullscreen(self, enabled):
        if enabled == self.fullscreen:
            return
        size = pygame.display.get_desktop_sizes()[0] if enabled else (WINDOW_WIDTH, WINDOW_HEIGHT)
        if size[0] < WINDOW_WIDTH or size[1] < WINDOW_HEIGHT:
            log.warning("Fullscreen requires at least %s x %s pixels; keeping windowed mode",
                        WINDOW_WIDTH, WINDOW_HEIGHT)
            return
        try:
            self.window = pygame.display.set_mode(size, pygame.FULLSCREEN if enabled else 0)
            if not enabled and self.window.get_size() != size:
                # Some SDL backends clear fullscreen first and resize on the next call.
                self.window = pygame.display.set_mode(size, 0)
            self.fullscreen = enabled
        except pygame.error as error:
            log.warning("Cannot change Gridlock display mode: %s", error)

    def to_logical(self, position):
        x, y = self.offset
        return position[0] - x, position[1] - y

    def translate_event(self, event):
        if hasattr(event, "pos"):
            return pygame.event.Event(event.type, {**event.dict, "pos": self.to_logical(event.pos)})
        return event

    def present(self):
        self.window.fill(BACKGROUND)
        self.window.blit(self.canvas, self.offset)
        pygame.display.flip()
