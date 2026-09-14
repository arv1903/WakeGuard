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


def test_perclos_single_closed_sample_is_one():
    p = PerclosTracker(window_seconds=10, sample_rate=2)
    assert p.update(True) == pytest.approx(1.0)


def test_perclos_reset_drops_stale_window():
    p = PerclosTracker(window_seconds=10, sample_rate=2)
    for _ in range(10):
        p.update(True)
    p.reset()
    # A fresh window with open samples must not inherit the old closures.
    assert p.update(False) == pytest.approx(0.0)


def test_ema_reset_zeroes_history():
    ema = DrowsyEMA(alpha=0.9)
    for _ in range(200):
        ema.update(1.0)
    ema.reset()
    assert ema.update(1.0) == pytest.approx(0.1)
