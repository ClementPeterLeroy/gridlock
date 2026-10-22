"""Match state, turns, history and Blitz timing."""

from dataclasses import dataclass, field
from rules import valid_moves, wall_error, reached_goal
from settings import PLAYER_NAMES

STARTS = ((8, 4), (0, 4), (4, 0), (4, 8))
# Clockwise around the board: bottom -> left -> top -> right.
FOUR_PLAYER_ORDER = (0, 2, 1, 3)


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
    time_left: list = field(default_factory=list)
    penalty_used: bool = False
    overtime: float = 0.0
    difficulty: str = "Casual"

    def __post_init__(self):
        count = 4 if self.mode == "Battle Royale" else 2
        if not self.pawns:
            self.pawns = list(STARTS[:count])
        if not self.walls_left:
            self.walls_left = [5] * count if count == 4 else [10] * count
        if not self.time_left:
            self.time_left = [180.0] * count

    @property
    def player_count(self):
        return len(self.pawns)

    @property
    def is_blitz(self):
        return self.mode == "Blitz"

    def snapshot(self):
        return (self.pawns.copy(), self.walls.copy(), self.walls_left.copy(),
                self.current_player, self.winner, self.turn_elapsed,
                self.time_left.copy(), self.penalty_used, self.overtime)

    def next_turn(self):
        if self.player_count == 4:
            order = FOUR_PLAYER_ORDER
            self.current_player = order[(order.index(self.current_player) + 1) % 4]
        else:
            self.current_player = 1 - self.current_player
        self.turn_elapsed = 0.0
        self.penalty_used = False
        self.overtime = 0.0
        if self.is_blitz:
            p = self.current_player
            self.time_left[p] = max(10.0, self.time_left[p])
        self.message = f"{PLAYER_NAMES[self.current_player]}'s turn."

    def move(self, target):
        if self.winner is not None or target not in valid_moves(self.pawns, self.current_player, self.walls):
            return False
        self.history.append(self.snapshot())
        self.pawns[self.current_player] = target
        if reached_goal(target, self.current_player):
            self.winner = self.current_player
            self.message = f"{PLAYER_NAMES[self.winner]} wins!"
        else:
            self.next_turn()
        return True

    def place_wall(self, wall):
        if self.winner is not None:
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

    def tick(self, seconds):
        """Advance active turn clock by elapsed real time in seconds."""
        if self.winner is not None:
            return
        seconds = max(0.0, seconds)
        self.turn_elapsed += seconds
        if not self.is_blitz:
            return
        p = self.current_player
        if self.penalty_used:
            self.overtime = max(0.0, self.overtime - seconds)
            if self.overtime <= 0:
                self.winner = 1 - p
                self.message = f"{PLAYER_NAMES[p]} ran out of time."
            return
        self.time_left[p] = max(0.0, self.time_left[p] - seconds)
        if self.time_left[p] > 0:
            return
        if self.walls_left[p] == 0:
            self.winner = 1 - p
            self.message = f"{PLAYER_NAMES[p]} ran out of time with no walls."
            return
        self.walls_left[p] -= 1
        self.penalty_used = True
        self.overtime = 15.0
        self.message = f"{PLAYER_NAMES[p]} loses a wall! 15 seconds left."

    def undo(self):
        if not self.history:
            self.message = "Nothing to undo."
            return False
        (self.pawns, self.walls, self.walls_left, self.current_player,
         self.winner, self.turn_elapsed, self.time_left,
         self.penalty_used, self.overtime) = self.history.pop()
        self.message = "Last turn undone."
        return True
