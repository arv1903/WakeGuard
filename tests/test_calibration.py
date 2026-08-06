import pytest

from yolo.calibration import CalibrationProfile, RunCalibration


def test_profile_roundtrip(tmp_path):
    p = CalibrationProfile(neutral_pitch=1.0, neutral_yaw=-2.0, neutral_roll=0.5)
    path = tmp_path / "driver.json"
    p.save(str(path))
    loaded = CalibrationProfile.load(str(path))
    assert loaded is not None
    assert loaded.neutral_pitch == pytest.approx(1.0)
    assert loaded.neutral_yaw == pytest.approx(-2.0)


def test_load_missing_returns_none(tmp_path):
    assert CalibrationProfile.load(str(tmp_path / "nope.json")) is None


def test_run_calibration_averages_pose():
    pose = {"pitch": 10.0, "yaw": -5.0, "roll": 3.0, "valid": True}
    profile = RunCalibration(lambda: pose, duration=0.5)
    assert profile.neutral_pitch == pytest.approx(10.0)
    assert profile.neutral_yaw == pytest.approx(-5.0)
    assert profile.neutral_roll == pytest.approx(3.0)


def test_run_calibration_raises_without_valid_pose():
    with pytest.raises(RuntimeError):
        RunCalibration(lambda: {"valid": False}, duration=0.1)
