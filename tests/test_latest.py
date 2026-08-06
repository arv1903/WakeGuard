from yolo.latest import LatestValue


def test_latest_keeps_newest_only():
    lv = LatestValue()
    lv.publish(1)
    lv.publish(2)
    lv.publish(3)
    assert lv.latest() == 3


def test_latest_starts_none():
    assert LatestValue().latest() is None
