import pytest
from yolo.attention import ComputeAttentionScore, UpdateTimer


def test_attention_perfect_is_100():
    assert ComputeAttentionScore(0.0, 0.0, 0.0) == 100.0


def test_attention_eye_penalty():
    score = ComputeAttentionScore(1.0, 0.0, 0.0)
    assert score == pytest.approx(50.0, abs=1e-6)  # 50 weight * 1.0


def test_attention_yaw_penalty_caps_at_weight():
    assert ComputeAttentionScore(0.0, 0.0, 90.0) == pytest.approx(70.0, abs=1e-6)


def test_attention_pitch_only_penalizes_down():
    down = ComputeAttentionScore(0.0, -30.0, 0.0)   # full 40 penalty
    up = ComputeAttentionScore(0.0, 30.0, 0.0)      # no penalty
    assert down == pytest.approx(60.0, abs=1e-6)
    assert up == 100.0


def test_attention_clamped_to_zero():
    assert ComputeAttentionScore(1.0, -90.0, 90.0) == 0.0


def test_timer_accumulates_and_fires():
    acc, fired = UpdateTimer(True, 0.0, 0.5, 2.0)
    assert acc == pytest.approx(0.5) and not fired
    acc, fired = UpdateTimer(True, acc, 1.6, 2.0)
    assert fired and acc == pytest.approx(2.1)


def test_timer_resets_when_condition_clears():
    acc, fired = UpdateTimer(False, 1.5, 0.5, 2.0)
    assert acc == 0.0 and not fired


def test_timer_freeze_preserves_progress():
    acc, fired = UpdateTimer(True, 1.0, 0.5, 2.0, Freeze=True)
    assert acc == pytest.approx(1.0) and not fired
