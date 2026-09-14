import pytest
from yolo.attention import (CapDeltaTime, ComputeAttentionScore,
                            StartupCountdown, UpdateTimer)


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


def test_cap_delta_time_passes_normal_frame_steps():
    assert CapDeltaTime(1.0 / 30.0) == pytest.approx(1.0 / 30.0)


def test_cap_delta_time_clamps_stalls():
    # A 5-minute idle before the first frame must not count as 300 s of
    # sustained condition time.
    assert CapDeltaTime(300.0) == pytest.approx(0.25)


def test_cap_delta_time_ignores_negative_steps():
    assert CapDeltaTime(-0.1) == 0.0


# ── StartupCountdown (wall-clock 3-2-1 grace) ──────────────────────


def test_countdown_counts_real_wall_time():
    cd = StartupCountdown(3.0)
    cd.start(now=100.0)
    assert cd.active(now=100.5)
    assert cd.remaining(now=100.5) == pytest.approx(2.5)
    assert cd.remaining(now=102.9) == pytest.approx(0.1)
    assert not cd.active(now=103.0)
    assert cd.remaining(now=104.0) == 0.0  # never goes negative


def test_countdown_independent_of_tick_cadence():
    # Sparse, irregular ticks (CPU-bound inference at ~2 Hz) must not stretch
    # the grace period: remaining follows wall-clock, not summed deltas.
    cd = StartupCountdown(3.0)
    cd.start(now=0.0)
    assert cd.remaining(now=0.7) == pytest.approx(2.3)  # one slow tick
    assert cd.remaining(now=1.3) == pytest.approx(1.7)
    assert cd.remaining(now=3.1) == 0.0


def test_countdown_zero_duration_disables_grace():
    cd = StartupCountdown(0.0)
    cd.start(now=100.0)
    assert not cd.active(now=100.0)
    assert cd.remaining(now=100.0) == 0.0


def test_countdown_restart_rearms_and_reset_cancels():
    cd = StartupCountdown(3.0)
    cd.start(now=100.0)
    assert cd.active(now=101.0)
    # Re-arm (Start clicked again mid-session) restarts from full duration.
    cd.start(now=101.0)
    assert cd.remaining(now=102.0) == pytest.approx(2.0)
    cd.reset()
    assert not cd.active(now=102.0)


def test_countdown_configure_after_construction():
    cd = StartupCountdown()
    assert not cd.active()  # default 0 = disabled
    cd.configure(5.0)
    cd.start(now=0.0)
    assert cd.remaining(now=4.0) == pytest.approx(1.0)
