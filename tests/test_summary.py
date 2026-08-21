from yolo.session_log import SessionLogger
from yolo.summary import BuildSummary


def test_build_summary(tmp_path):
    path = tmp_path / "s.jsonl"
    log = SessionLogger(str(path))
    log.frame_sample(90.0, 0.1, 0.2, 0.0, 0.0, 0.0, True, None)
    log.alert_event("yolo", 2.0)
    # Frame entries carry the *current* alert label but must NOT be counted
    # as alert transitions — only explicit 'alert' type events count.
    log.frame_sample(40.0, 0.6, 0.8, -25.0, 0.0, 0.0, True, "yolo")
    log.alert_event("perclos", 1.5)
    log.close()

    s = BuildSummary(str(path))
    assert s["alert_count"] == 2
    assert s["alerts_by_type"] == {"yolo": 1, "perclos": 1}
    assert s["attention_min"] == 40.0
    assert s["attention_avg"] == 65.0
    assert s["perclos_max"] == 0.6
