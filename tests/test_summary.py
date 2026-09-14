from yolo.score import compute_safety_score
from yolo.session_log import SessionLogger
from yolo.summary import (
    BuildSummary,
    PrintSummary,
    _build_summary_from_db,
)


class _FakeResponse:
    def __init__(self, data):
        self.data = data


class _FakeQuery:
    def __init__(self, data):
        self._data = data

    def select(self, *_) -> "_FakeQuery":
        return self

    def eq(self, *_) -> "_FakeQuery":
        return self

    def order(self, *_, **__) -> "_FakeQuery":
        return self

    def limit(self, _) -> "_FakeQuery":
        return self

    def execute(self):
        return _FakeResponse(self._data)


class _FakeDb:
    def __init__(self, tables):
        self._tables = tables

    def table(self, name):
        return _FakeQuery(self._tables.get(name, []))


def test_build_summary_includes_safety_score(tmp_path):
    path = tmp_path / "s.jsonl"
    log = SessionLogger(str(path))
    log.frame_sample(90.0, 0.1, 0.2, 0.0, 0.0, 0.0, True, None)
    log.alert_event("yolo", 2.0)
    log.close()

    s = BuildSummary(str(path))
    assert s["safety_score"] == compute_safety_score(90.0, 1)


def test_build_summary_empty_log_safety_score_is_zero(tmp_path):
    summary = BuildSummary(str(tmp_path / "missing.jsonl"))
    assert summary["safety_score"] == 0.0


def test_summary_from_db_fast_path_passes_through_safety_score():
    # Row stores safety_score=99 while avg_attention=91.5 and alert_count=1
    # would recompute to 88.5 — the stored value must win (no divergence).
    db = _FakeDb({
        "sessions": [{
            "duration_s": 120.0,
            "avg_attention": 91.5,
            "avg_perclos": 0.2,
            "alert_count": 1,
            "safety_score": 99,
            "alerts_by_type": '{"yolo": 1}',
        }],
    })
    s = _build_summary_from_db(db, "sess-1")
    assert s["safety_score"] == 99
    assert s["alert_count"] == 1
    assert s["alerts_by_type"] == {"yolo": 1}


def test_summary_from_db_fallback_computes_score_and_alert_times():
    db = _FakeDb({
        "sessions": [{"duration_s": None}],  # forces fallback
        "telemetry": [
            {"attention": 90.0, "perclos": 0.1, "blinks_per_min": 15.0},
            {"attention": 80.0, "perclos": 0.2, "blinks_per_min": 17.0},
        ],
        "alert_events": [
            {"alert": "yolo", "ts": 1000.0},
            {"alert": "perclos", "ts": 1180.0},
        ],
    })
    s = _build_summary_from_db(db, "sess-1")
    assert s["alert_times"] == [1000.0, 1180.0]
    assert s["alerts_by_type"] == {"yolo": 1, "perclos": 1}
    assert s["avg_attention"] == 85.0
    assert s["safety_score"] == compute_safety_score(85.0, 2)


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
