import json

from yolo.session_log import SessionLogger


def test_roundtrip(tmp_path):
    path = tmp_path / "s.jsonl"
    log = SessionLogger(str(path))
    log.frame_sample(90.0, 0.1, 0.2, 5.0, -2.0, 1.0, True, None)
    log.alert_event("yolo", 3.0)
    log.close()

    lines = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
    assert len(lines) == 2
    assert lines[0]["type"] == "frame" and lines[0]["attention"] == 90.0
    assert lines[1]["type"] == "alert" and lines[1]["alert"] == "yolo"
    assert "ts" in lines[0]
