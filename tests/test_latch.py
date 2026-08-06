from yolo.attention import AlertLatch


def test_fires_and_holds_while_condition_true():
    latch = AlertLatch(clear_seconds=2.0)
    assert latch.update(True, 0.1)
    assert latch.update(True, 0.1)


def test_holds_after_condition_clears_until_grace():
    latch = AlertLatch(clear_seconds=2.0)
    latch.update(True, 0.1)
    assert latch.update(False, 1.0)   # still active (1.0s < 2.0s grace)
    assert not latch.update(False, 1.5)   # 2.5s clean → released on this call
    assert not latch.update(False, 0.1)


def test_reactivates_immediately():
    latch = AlertLatch(clear_seconds=2.0)
    latch.update(True, 0.1)
    latch.update(False, 3.0)          # released
    assert latch.update(True, 0.1)
