import time

from yolo.stats import PerfStats


def test_stats_mean_zero_before_recording():
    assert PerfStats().mean("yolo") == 0.0


def test_stats_records_stage_mean():
    s = PerfStats(window_frames=10)
    for _ in range(5):
        s.tick()
        time.sleep(0.001)
        s.tock("yolo")
    mean = s.mean("yolo")
    assert 0.5 < mean < 5.0  # ~1 ms per sample


def test_stats_snapshot_keys():
    s = PerfStats()
    s.tick()
    s.tock("draw")
    assert set(s.snapshot()) == {"draw"}
