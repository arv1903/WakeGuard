import pytest

from yolo.perclos import DrowsyEMA, PerclosTracker


def test_ema_converges_to_one():
    ema = DrowsyEMA(alpha=0.9)
    for _ in range(200):
        ema.update(1.0)
    assert ema.update(1.0) > 0.99


def test_ema_responsive_to_drop():
    ema = DrowsyEMA(alpha=0.9)
    for _ in range(200):
        ema.update(1.0)
    assert ema.update(0.0) < 0.95


def test_perclos_all_closed_is_one():
    p = PerclosTracker(window_seconds=10, sample_rate=2)
    for _ in range(20):
        p.update(True)
    assert p.update(True) == pytest.approx(1.0)


def test_perclos_half_closed():
    p = PerclosTracker(window_seconds=10, sample_rate=2)
    for i in range(20):
        p.update(i % 2 == 0)
    assert p.update(True) == pytest.approx(0.5, abs=0.1)


def test_perclos_empty_window_returns_zero():
    p = PerclosTracker(window_seconds=10, sample_rate=2)
    assert p.update(True) == pytest.approx(1.0)
