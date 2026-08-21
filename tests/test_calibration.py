import pytest

from yolo.calibration import CalibrationProfile, CalibrationSession, RunCalibration


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


def test_calibration_session_non_blocking():
    session = CalibrationSession(duration=2.0)
    assert not session.is_active
    assert not session.is_finished
    session.start(now=100.0)
    assert session.is_active

    # Step 1: at t=101.0 (50% progress)
    p1 = session.update({"pitch": 12.0, "yaw": -4.0, "roll": 2.0, "valid": True}, now=101.0)
    assert p1 == pytest.approx(0.5)
    assert not session.is_finished

    # Step 2: at t=102.0 (100% progress)
    p2 = session.update({"pitch": 10.0, "yaw": -6.0, "roll": 4.0, "valid": True}, now=102.0)
    assert p2 == pytest.approx(1.0)
    assert session.is_finished

    profile = session.finish()
    assert profile.neutral_pitch == pytest.approx(11.0)
    assert profile.neutral_yaw == pytest.approx(-5.0)
    assert profile.neutral_roll == pytest.approx(3.0)


def test_calibration_session_exposes_progress_and_valid_sample_count():
    session = CalibrationSession(duration=2.0)
    assert session.progress == 0.0
    assert session.valid_samples == 0

    session.start(now=10.0)
    session.update({"valid": False}, now=10.5)
    assert session.progress == pytest.approx(0.25)
    assert session.valid_samples == 0

    session.update({"pitch": 1.0, "yaw": 2.0, "roll": 3.0, "valid": True}, now=11.0)
    assert session.progress == pytest.approx(0.5)
    assert session.valid_samples == 1


def test_calibration_restart_resets_exposed_state():
    session = CalibrationSession(duration=1.0)
    session.start(now=1.0)
    session.update({"pitch": 1.0, "yaw": 2.0, "roll": 3.0, "valid": True}, now=2.0)
    assert session.progress == 1.0

    session.start(now=5.0)
    assert session.progress == 0.0
    assert session.valid_samples == 0
    assert session.is_active
