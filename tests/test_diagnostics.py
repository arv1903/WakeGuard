import pytest

from yolo import diagnostics


@pytest.mark.integration
def test_diagnostics_accepts_camera():
    # Requires a webcam; skipped in fast runs.
    problems = diagnostics.RunDiagnostics(0, no_alarm=True, no_telegram=True)
    assert "Cannot read from source: 0" not in problems


def test_diagnostics_flags_missing_models(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    problems = diagnostics.RunDiagnostics("missing.mp4", no_alarm=True,
                                          no_telegram=True)
    assert any("best.pt" in p for p in problems)
    assert any("face_landmarker.task" in p for p in problems)
