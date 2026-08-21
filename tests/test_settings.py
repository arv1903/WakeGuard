import json
import math

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


@pytest.mark.parametrize("value", [math.nan, math.inf, -math.inf])
def test_validate_runtime_settings_rejects_non_finite_values(value):
    with pytest.raises(ValueError, match="finite"):
        config.ValidateRuntimeSettings({"ear_threshold": value})


def test_validate_runtime_settings_normalizes_aliases_without_mutating_config():
    original = config.EarClosedThreshold

    validated = config.ValidateRuntimeSettings({
        "ear_threshold": 0.25,
        "logging_enabled": False,
        "perclos_threshold": 0.4,
    })

    assert validated == {
        "EarClosedThreshold": 0.25,
        "SessionLoggingEnabled": False,
        "PerclosAlertThreshold": 0.4,
    }
    assert config.EarClosedThreshold == original


def test_update_thresholds_is_atomic_when_one_value_is_invalid():
    original_ear = config.EarClosedThreshold
    original_pitch = config.HeadDownPitch

    with pytest.raises(ValueError):
        config.UpdateThresholds({
            "EarClosedThreshold": 0.25,
            "HeadDownPitch": 100,
        })

    assert config.EarClosedThreshold == original_ear
    assert config.HeadDownPitch == original_pitch


def test_removed_legacy_hud_setting_is_rejected():
    with pytest.raises(ValueError, match="Unknown setting"):
        config.ValidateRuntimeSettings({"PilHud": False})
