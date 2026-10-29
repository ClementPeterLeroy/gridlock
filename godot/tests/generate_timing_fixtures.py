"""Reference timing traces from the unchanged Pygame Game model."""

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "pygame"))
from game import Game
from match_config import MatchConfig

OUTPUT = Path(__file__).parent / "core" / "python_timing_parity.json"


def normalized(game):
    return {
        "turn_elapsed": game.turn_elapsed,
        "turn_clock_elapsed": game.turn_clock_elapsed,
        "time_left": game.time_left.copy(),
        "penalty_used": game.penalty_used,
        "overtime": game.overtime,
        "remaining": None if game.remaining_turn_time == float("inf") else game.remaining_turn_time,
        "current_player": game.current_player,
        "winner": -1 if game.winner is None else game.winner,
        "pawns": [None if p is None else [p[1], p[0]] for p in game.pawns],
        "walls_left": game.walls_left.copy(),
        "walls": sorted([[c, r, d] for r, c, d in game.walls]),
        "active": game.active_players,
        "paused": game.paused,
        "history_size": len(game.history),
    }


def scenario(name, mode, operations, limit=0, minutes=3):
    config = MatchConfig.for_mode(mode)
    config.turn_limit, config.blitz_minutes = limit, minutes
    game = Game(mode, config=config)
    steps = [{"op": {"kind": "initial"}, "state": normalized(game)}]
    for op in operations:
        accepted = None
        match op["kind"]:
            case "tick":
                game.tick(op["seconds"], op.get("charge"))
            case "set":
                for key, value in op["values"].items():
                    if key == "pawns":
                        value = [(p[1], p[0]) for p in value]
                    setattr(game, key, value.copy() if isinstance(value, list) else value)
            case "move":
                c, r = op["target"]
                accepted = game.move((r, c))
            case "wall":
                c, r, direction = op["target"]
                accepted = game.place_wall((r, c, direction))
            case "next":
                game.next_turn()
            case "pause":
                game.paused = op["value"]
            case "undo":
                accepted = game.undo()
        steps.append({"op": op, "accepted": accepted, "state": normalized(game)})
    return {"name": name, "mode": mode, "limit": limit, "minutes": minutes, "steps": steps}


def tick(seconds, charge=None):
    return {"kind": "tick", "seconds": seconds, **({"charge": charge} if charge is not None else {})}


def put(**values):
    return {"kind": "set", "values": values}


def move(c, r):
    return {"kind": "move", "target": [c, r]}


def build():
    traces = []
    traces.append(scenario("untimed_elapsed_undo", "Versus", [
        tick(-2), tick(1.25), move(4, 7), tick(2), {"kind": "undo"}, tick(100000)]))
    for mode in ("Versus", "Battle Royale"):
        for limit in (15, 30, 60, 120):
            traces.append(scenario(f"{mode}_{limit}_expiry", mode, [
                tick(limit - 0.125), tick(0.125), move(4, 7), {"kind": "undo"}], limit=limit))
    traces.append(scenario("four_player_elimination_and_walls", "Battle Royale", [
        {"kind": "wall", "target": [3, 3, "H"]}, tick(15), tick(15), tick(15),
        tick(100), {"kind": "undo"}, {"kind": "next"}, {"kind": "next"}], limit=15))
    for minutes in (1, 3, 5):
        traces.append(scenario(f"blitz_{minutes}_floor_penalty", "Blitz", [
            put(time_left=[60 * minutes, 2]), move(4, 7), tick(10),
            tick(14.5), tick(0.5), tick(100), {"kind": "undo"}], minutes=minutes))
    traces.append(scenario("blitz_no_walls", "Blitz", [
        put(time_left=[0.5, 180], walls_left=[0, 10]), tick(1), move(4, 7)]))
    traces.append(scenario("blitz_large_delta_fresh_overtime", "Blitz", [
        put(time_left=[1, 180]), tick(1000), tick(14), tick(1)]))
    traces.append(scenario("blitz_successive_turn_penalties_and_undo", "Blitz", [
        put(time_left=[1, 50]), tick(1), {"kind": "wall", "target": [3, 3, "H"]},
        tick(2), move(4, 1), tick(10), move(4, 7), {"kind": "undo"}, tick(3),
        {"kind": "wall", "target": [3, 3, "V"]}]))
    for mode in ("Versus", "Battle Royale", "Blitz"):
        traces.append(scenario(f"{mode}_pause_resume", mode, [
            tick(1), {"kind": "pause", "value": True}, tick(10000), move(4, 7),
            {"kind": "pause", "value": False}, tick(2), move(4, 7), {"kind": "undo"}], limit=15))
        traces.append(scenario(f"{mode}_AI_charge_reference", mode, [
            tick(0.75, 0), tick(0.5, 0.25), tick(2, 2), move(4, 7),
            {"kind": "undo"}, tick(100, 100)], limit=15))
        traces.append(scenario(f"{mode}_victory_freezes_time", mode, [
            put(pawns=[[2, 1], [4, 0]] + ([[0, 4], [8, 4]] if mode == "Battle Royale" else [])),
            tick(1), move(2, 0), tick(10000)], limit=15))
    return {"reference": "pygame/game.py", "traces": traces}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    options = parser.parse_args()
    data = build()
    encoded = json.dumps(data, indent=2) + "\n"
    if options.check:
        if OUTPUT.read_text(encoding="utf-8") != encoded:
            raise SystemExit("Python timing fixtures are stale")
        print("Python timing fixtures match unchanged Classic timing")
    else:
        OUTPUT.write_text(encoded, encoding="utf-8")
        print(f"Wrote {len(data['traces'])} timing traces, {sum(len(t['steps']) for t in data['traces'])} states")


if __name__ == "__main__":
    main()
