"""Trip summary computed from a session log."""

import json
from collections import Counter


def BuildSummary(log_path: str) -> dict:
    attentions, perclos = [], []
    alerts, alert_times = [], []
    start_ts = end_ts = None
    with open(log_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            ev = json.loads(line)
            ts = ev.get("ts", 0.0)
            start_ts = ts if start_ts is None else start_ts
            end_ts = ts
            if ev["type"] == "frame":
                attentions.append(ev.get("attention", 0.0))
                perclos.append(ev.get("perclos", 0.0))
                if ev.get("alert"):
                    alerts.append(ev["alert"])
                    alert_times.append(ts)
            elif ev["type"] == "alert":
                alerts.append(ev["alert"])
                alert_times.append(ts)
            # "clear" events are intentionally ignored: only alert starts
            # count toward alert_count and the timeline.
    return {
        "duration": (end_ts - start_ts) if start_ts is not None else 0.0,
        "attention_min": min(attentions) if attentions else None,
        "attention_avg": (sum(attentions) / len(attentions)) if attentions else None,
        "perclos_max": max(perclos) if perclos else None,
        "alert_count": len(alerts),
        "alerts_by_type": dict(Counter(alerts)),
        "alert_times": alert_times,
    }


def PrintSummary(summary: dict) -> None:
    print("── Trip Summary ─────────────────────────────")
    print(f"Duration:      {summary['duration']:.0f}s")
    print(f"Attention avg: {summary['attention_avg']:.0f}  min: {summary['attention_min']:.0f}")
    print(f"PERCLOS max:   {summary['perclos_max']:.0%}")
    print(f"Alerts:        {summary['alert_count']}  {summary['alerts_by_type']}")


def WriteReport(summary: dict, out_path: str) -> None:
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("# Trip Report\n\n")
        for k, v in summary.items():
            f.write(f"- **{k}:** {v}\n")
