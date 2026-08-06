import json

import pytest

from yolo import config


def test_load_settings_overrides(tmp_path):
    path = tmp_path / "s.json"
    path.write_text(json.dumps({"YoloDrowsyThreshold": 0.6}))
    config.LoadSettings(str(path))
    assert config.YoloDrowsyThreshold == 0.6
    config.LoadSettings(None)          # no-op


def test_load_settings_rejects_unknown_key(tmp_path):
    path = tmp_path / "s.json"
    path.write_text(json.dumps({"Nope": 1}))
    with pytest.raises(ValueError):
        config.LoadSettings(str(path))


def test_load_settings_rejects_non_numeric(tmp_path):
    path = tmp_path / "s.json"
    path.write_text(json.dumps({"YoloDrowsyThreshold": "high"}))
    with pytest.raises(ValueError):
        config.LoadSettings(str(path))
