import json

from yolo.eval import evaluate, load_alerts, parse_labels


def test_evaluate_perfect():
    res = evaluate([1.0], [(0, 10)])
    assert res["tp"] == 1 and res["fp"] == 0 and res["fn"] == 0
    assert res["precision"] == 1.0 and res["recall"] == 1.0 and res["f1"] == 1.0


def test_evaluate_false_positive():
    res = evaluate([100.0], [(0, 10)])
    assert res["fp"] == 1 and res["precision"] == 0.0


def test_evaluate_missed_period():
    res = evaluate([], [(0, 10)])
    assert res["fn"] == 1 and res["recall"] == 0.0


def test_evaluate_within_tolerance_counts():
    # 4s after the period end is inside the 5s tolerance.
    res = evaluate([14.0], [(0, 10)])
    assert res["tp"] == 1 and res["fp"] == 0


def test_load_alerts_relative_to_first_frame(tmp_path):
    path = tmp_path / "s.jsonl"
    with open(path, "w", encoding="utf-8") as f:
        f.write(json.dumps({"ts": 1000.0, "type": "frame", "alert": None}) + "\n")
        f.write(json.dumps({"ts": 1005.5, "type": "alert", "alert": "yolo"}) + "\n")
    assert load_alerts(str(path)) == [5.5]


def test_parse_labels(tmp_path):
    path = tmp_path / "l.jsonl"
    path.write_text(json.dumps({"start": 1.0, "end": 2.0, "label": "drowsy"}) + "\n")
    assert parse_labels(str(path)) == [(1.0, 2.0)]
