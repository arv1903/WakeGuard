from yolo.latest import LatestValue


def test_latest_keeps_newest_only():
    lv = LatestValue()
    lv.publish(1)
    lv.publish(2)
    lv.publish(3)
    assert lv.latest() == 3


def test_latest_starts_none():
    assert LatestValue().latest() is None


def test_wait_for_new_timeout_returns_none():
    lv = LatestValue()
    val, version = lv.wait_for_new(0, timeout=0.01)
    assert val is None
    assert version == 0


def test_wait_for_new_returns_value():
    lv = LatestValue()
    lv.publish("frame1")
    val, version = lv.wait_for_new(0, timeout=0.1)
    assert val == "frame1"
    assert version == 1
