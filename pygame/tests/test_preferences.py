"""Settings persistence without touching the user's settings.json."""

import json
import sys
import unittest
from pathlib import Path
from uuid import uuid4
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from preferences import load_settings, save_settings, DEFAULT_SETTINGS


class PreferencesTests(unittest.TestCase):
    def setUp(self):
        self.path = Path(__file__).parent / f'.preferences-test-{uuid4().hex}.json'
        self.addCleanup(lambda: self.path.unlink(missing_ok=True))

    def test_round_trip_and_missing_file_creation(self):
        self.assertEqual(load_settings(self.path), DEFAULT_SETTINGS)
        self.assertTrue(self.path.is_file())
        options = {'Music': False, 'Sound Effects': True, 'Animations': False}
        self.assertTrue(save_settings(options, self.path))
        self.assertEqual(load_settings(self.path), options)

    def test_invalid_types_and_unknown_keys(self):
        self.path.write_text(json.dumps({'Music': False, 'Animations': 'false', 'Sound Effects': 0, 'Other': True}))
        self.assertEqual(load_settings(self.path), {'Music': False, 'Sound Effects': True, 'Animations': True})

    def test_corrupt_file_falls_back_without_overwriting(self):
        for contents in ('{broken', '[]'):
            self.path.write_text(contents)
            with self.assertLogs('preferences', level='WARNING'):
                self.assertEqual(load_settings(self.path), DEFAULT_SETTINGS)
            self.assertEqual(self.path.read_text(), contents)

    def test_write_failure_keeps_previous_settings(self):
        self.path.write_text('{"Music": false}')
        with patch('preferences.os.replace', side_effect=PermissionError('read only')), \
             self.assertLogs('preferences', level='WARNING'):
            self.assertFalse(save_settings(DEFAULT_SETTINGS, self.path))
        self.assertEqual(self.path.read_text(), '{"Music": false}')
