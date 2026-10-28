"""Load and save the three application settings beside the game."""

import json
import logging
import os
from pathlib import Path
import tempfile

SETTINGS_FILE = Path(__file__).resolve().with_name("settings.json")
DEFAULT_SETTINGS = {"Music": True, "Sound Effects": True, "Animations": True}
log = logging.getLogger(__name__)


def load_settings(path=SETTINGS_FILE):
    options = DEFAULT_SETTINGS.copy()
    try:
        saved = json.loads(Path(path).read_text(encoding="utf-8-sig"))
        if not isinstance(saved, dict):
            raise ValueError("settings must be a JSON object")
        for name in options:
            if type(saved.get(name)) is bool:
                options[name] = saved[name]
    except FileNotFoundError:
        save_settings(options, path)
    except (OSError, ValueError) as error:
        log.warning("Cannot read Gridlock settings %s; using defaults (%s)", path, error)
    return options


def save_settings(options, path=SETTINGS_FILE):
    """Replace atomically so interrupted writes do not truncate saved settings."""
    path = Path(path)
    temporary = None
    try:
        data = {}
        for name, default in DEFAULT_SETTINGS.items():
            value = options.get(name, default)
            data[name] = value if type(value) is bool else default
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix=".gridlock-settings-", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(json.dumps(data, indent=2) + "\n")
        os.replace(temporary, path)
        temporary = None
        return True
    except OSError as error:
        log.warning("Cannot save Gridlock settings %s (%s)", path, error)
        return False
    finally:
        if temporary is not None:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass
