from yolo.session_log import SessionLogger
from yolo.summary import BuildSummary, PrintSummary


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


def test_print_summary_with_data(capsys):
    # Regression: conditional expressions inside f-string format specs
    # ({v:.0f if v is not None else 0}) are invalid and always raised.
    summary = {
        "duration": 62.4,
        "attention_avg": 65.0,
        "attention_min": 40.0,
        "perclos_max": 0.6,
        "alert_count": 2,
        "alerts_by_type": {"yolo": 1, "perclos": 1},
    }
    PrintSummary(summary)
    out = capsys.readouterr().out
    assert "Duration:      62s" in out
    assert "Attention avg: 65  min: 40" in out
    assert "PERCLOS max:   60%" in out
    assert "Alerts:        2  {'yolo': 1, 'perclos': 1}" in out


def test_print_summary_empty_log(tmp_path, capsys):
    summary = BuildSummary(str(tmp_path / "missing.jsonl"))
    assert summary["attention_avg"] is None
    PrintSummary(summary)
    out = capsys.readouterr().out
    assert "Duration:      0s" in out
    assert "Attention avg: 0  min: 0" in out
    assert "PERCLOS max:   0" in out
    assert "Alerts:        0  {}" in out
