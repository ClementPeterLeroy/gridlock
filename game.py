"""Match state, turns, history and Blitz timing."""

from dataclasses import dataclass, field
from rules import valid_moves, wall_error, reached_goal
from settings import PLAYER_NAMES
from match_config import MatchConfig, clean_name, CONTROL_OPTIONS

STARTS = ((8, 4), (0, 4), (4, 0), (4, 8))
# Clockwise around the board: bottom -> left -> top -> right.
FOUR_PLAYER_ORDER = (0, 2, 1, 3)
DEFAULT_BR_CONTROLS = ("Human", "AI - Casual", "AI - Casual", "AI - Casual")


@dataclass
class Game:
    mode: str = "Versus"
    pawns: list = field(default_factory=list)
    walls: set = field(default_factory=set)
    walls_left: list = field(default_factory=list)
    current_player: int = 0
    winner: int | None = None
    history: list = field(default_factory=list)
    message: str = "Click your pawn to see its moves."
    turn_elapsed: float = 0.0
    turn_clock_elapsed: float = 0.0
    time_left: list = field(default_factory=list)
    penalty_used: bool = False
    overtime: float = 0.0
    difficulty: str = "Casual"
    controllers: list = field(default_factory=list)
    config: MatchConfig | None = None
    eliminated: set = field(default_factory=set)
    paused: bool = False

    def __post_init__(self):
        if self.config is None:
            self.config = MatchConfig(mode=self.mode)
        else:
            self.controllers = self.config.controllers.copy()
        count = 4 if self.mode == "Battle Royale" else 2
        if not self.pawns:
            self.pawns = list(STARTS[:count])
        if not self.walls_left:
            self.walls_left = [5] * count if count == 4 else [10] * count
        if not self.time_left:
            self.time_left = [60.0 * self.config.blitz_minutes] * count

    @property
    def player_count(self):
        return len(self.pawns)

    @property
    def is_blitz(self):
        return self.mode == "Blitz"

    def controller(self, player):
        if self.controllers:
            return self.controllers[player]
        if self.mode == "Rise of the Machines" and player == 1:
            return f"AI - {self.difficulty}"
        return "Human"

    @property
    def is_ai_turn(self):
        return self.winner is None and self.controller(self.current_player) != "Human"

    @property
    def ai_difficulty(self):
        return self.controller(self.current_player).removeprefix("AI - ")

    def display_name(self, player):
        return (PLAYER_NAMES[player] if self.controller(player) != "Human" else
                clean_name(self.config.names[player], player))

    def player_label(self, player):
        name = self.display_name(player)
        return name if name == PLAYER_NAMES[player] else f"{name} ({PLAYER_NAMES[player]})"

    @property
    def active_players(self):
        order = FOUR_PLAYER_ORDER if self.player_count == 4 else (0, 1)
        return [p for p in order if p not in self.eliminated]

    @property
    def remaining_turn_time(self):
        if self.is_blitz:
            return self.overtime if self.penalty_used else self.time_left[self.current_player]
        return max(0.0, self.config.turn_limit - self.turn_clock_elapsed) if self.config.turn_limit else float("inf")

    def snapshot(self):
        return (self.pawns.copy(), self.walls.copy(), self.walls_left.copy(),
                self.current_player, self.winner, self.turn_elapsed,
                self.time_left.copy(), self.penalty_used, self.overtime,
                self.eliminated.copy(), self.turn_clock_elapsed)

    def next_turn(self):
        if self.player_count == 4:
            order = FOUR_PLAYER_ORDER
            index = order.index(self.current_player)
            self.current_player = next(order[(index + step) % 4] for step in range(1, 5)
                                       if order[(index + step) % 4] not in self.eliminated)
        else:
            self.current_player = 1 - self.current_player
        self.turn_elapsed = 0.0
        self.turn_clock_elapsed = 0.0
        self.penalty_used = False
        self.overtime = 0.0
        if self.is_blitz:
            p = self.current_player
            self.time_left[p] = max(10.0, self.time_left[p])
        self.message = f"{self.player_label(self.current_player)}'s turn."

    def move(self, target):
        if self.paused or self.winner is not None or target not in valid_moves(self.pawns, self.current_player, self.walls):
            return False
        self.history.append(self.snapshot())
        self.pawns[self.current_player] = target
        if reached_goal(target, self.current_player):
            self.winner = self.current_player
            self.message = f"{self.player_label(self.winner)} wins!"
        else:
            self.next_turn()
        return True

    def place_wall(self, wall):
        if self.paused or self.winner is not None:
            return False
        error = wall_error(wall, self.walls, self.pawns, self.walls_left[self.current_player])
        if error:
            self.message = error
            return False
        self.history.append(self.snapshot())
        self.walls.add(wall)
        self.walls_left[self.current_player] -= 1
        self.next_turn()
        return True

    def tick(self, seconds, clock_seconds=None):
        """Track elapsed time separately from chargeable countdown time.

        Human turns charge all elapsed time. The UI can exempt AI presentation
        time from countdowns while still showing a live elapsed turn timer.
        """
        if self.paused or self.winner is not None:
            return
        seconds = max(0.0, seconds)
        clock_seconds = seconds if clock_seconds is None else max(0.0, clock_seconds)
        self.turn_elapsed += seconds
        self.turn_clock_elapsed += clock_seconds
        if not self.is_blitz and self.config.turn_limit and self.turn_clock_elapsed >= self.config.turn_limit:
            self.forfeit()
            return
        if not self.is_blitz:
            return
        p = self.current_player
        if self.penalty_used:
            self.overtime = max(0.0, self.overtime - clock_seconds)
            if self.overtime <= 0:
                self.winner = 1 - p
                self.message = f"{self.player_label(p)} ran out of time."
            return
        self.time_left[p] = max(0.0, self.time_left[p] - clock_seconds)
        if self.time_left[p] > 0:
            return
        if self.walls_left[p] == 0:
            self.winner = 1 - p
            self.message = f"{self.player_label(p)} ran out of time with no walls."
            return
        self.walls_left[p] -= 1
        self.penalty_used = True
        self.overtime = 15.0
        self.message = f"{self.player_label(p)} loses a wall! 15 seconds left."

    def forfeit(self):
        """Remove timed-out pawns; their placed walls remain on the board."""
        player = self.current_player
        self.history.append(self.snapshot())
        self.eliminated.add(player)
        self.pawns[player] = None
        if len(self.active_players) == 1:
            self.winner = self.active_players[0]
        else:
            self.next_turn()
        self.message = f"{self.player_label(player)} ran out of time and forfeited."

    def undo(self):
        if not self.history:
            self.message = "Nothing to undo."
            return False
        (self.pawns, self.walls, self.walls_left, self.current_player,
         self.winner, self.turn_elapsed, self.time_left,
         self.penalty_used, self.overtime, self.eliminated, self.turn_clock_elapsed) = self.history.pop()
        self.message = "Last turn undone."
        return True
