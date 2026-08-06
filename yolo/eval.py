"""Alert evaluation: precision/recall against labeled drowsy periods."""

import json

TOLERANCE_SECONDS = 5.0


def parse_labels(path):
    """Parse label periods [(start, end), ...] from a JSONL file."""
    periods = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                ev = json.loads(line)
                periods.append((ev["start"], ev["end"]))
    return periods


def load_alerts(log_path):
    """Alert timestamps (seconds) relative to the first logged frame."""
    alerts = []
    t0 = None
    with open(log_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            ev = json.loads(line)
            if ev["type"] == "frame" and t0 is None:
                t0 = ev["ts"]
            elif ev["type"] == "alert":
                alerts.append(ev["ts"])
    if t0 is not None:
        alerts = [ts - t0 for ts in alerts]
    return alerts


def evaluate(alerts, periods):
    """Compare fired alert times to labeled periods within a tolerance.

    Returns dict with tp, fp, fn, precision, recall, f1.
    """
    tp = fp = 0
    matched = [False] * len(periods)
    for ts in alerts:
        hit = False
        for i, (s, e) in enumerate(periods):
            if s - TOLERANCE_SECONDS <= ts <= e + TOLERANCE_SECONDS:
                hit = True
                matched[i] = True
        tp += 1 if hit else 0
        fp += 0 if hit else 1
    fn = matched.count(False)
    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = (2 * precision * recall / (precision + recall)
          if (precision + recall) else 0.0)
    return {"tp": tp, "fp": fp, "fn": fn,
            "precision": precision, "recall": recall, "f1": f1}
