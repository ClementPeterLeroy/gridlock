"""Session-only match options, separate from board rules."""

from dataclasses import dataclass, field
from settings import PLAYER_NAMES

NAME_LIMIT = 12
CONTROL_OPTIONS = ("Human", "AI - Casual", "AI - Challenging")


def clean_name(value, player):
    return "".join(c for c in value if c.isprintable()).strip()[:NAME_LIMIT] or PLAYER_NAMES[player]


@dataclass
class MatchConfig:
    mode: str = "Versus"
    names: list = field(default_factory=lambda: [""] * 4)
    controllers: list = field(default_factory=list)
    random_start: bool = False
    turn_limit: int = 0
    blitz_minutes: int = 3

    @classmethod
    def for_mode(cls, mode):
        controls = (["Human", "AI - Casual", "AI - Casual", "AI - Casual"]
                    if mode == "Battle Royale" else
                    ["Human", "AI - Casual"] if mode == "Rise of the Machines" else
                    ["Human", "Human"])
        return cls(mode=mode, controllers=controls)
