"""Trip summary computed from a session log."""

import json
from collections import Counter

from .score import compute_safety_score


def BuildSummary(log_path: str, session_id: str | None = None) -> dict:
    attentions, perclos = [], []
    blinks = []
    alerts, alert_times = [], []
    start_ts = end_ts = None
    try:
        with open(log_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                ev = json.loads(line)
                if session_id is not None and ev.get("session_id") != session_id:
                    continue
                ts = ev.get("ts", 0.0)
                start_ts = ts if start_ts is None else start_ts
                end_ts = ts
                if ev["type"] == "frame":
                    attentions.append(ev.get("attention", 0.0))
                    perclos.append(ev.get("perclos", 0.0))
                    if "blinks_per_min" in ev:
                        blinks.append(ev["blinks_per_min"])
                elif ev["type"] == "alert":
                    # Only count explicit alert transitions — never the
                    # 1-Hz "frame" samples, which double-count.
                    alerts.append(ev["alert"])
                    alert_times.append(ts)
                # "clear" and "session_start"/"session_stop" events are
                # intentionally ignored.
    except FileNotFoundError:
        pass

    duration = (end_ts - start_ts) if start_ts is not None else 0.0
    att_min = min(attentions) if attentions else None
    att_avg = (sum(attentions) / len(attentions)) if attentions else None
    p_max = max(perclos) if perclos else None
    blink_avg = (sum(blinks) / len(blinks)) if blinks else 0.0

    return {
        "duration": duration,
        "trip_duration_s": duration,
        "attention_min": att_min,
        "attention_avg": att_avg,
        "avg_attention": att_avg if att_avg is not None else 0.0,
        "perclos_max": p_max,
        "max_perclos": p_max if p_max is not None else 0.0,
        "alert_count": len(alerts),
        "avg_blinks_per_min": blink_avg,
        "alerts_by_type": dict(Counter(alerts)),
        "alert_times": alert_times,
    }


def BuildSessionHistory(log_path: str, limit: int = 10) -> list[dict]:
    """Parse distinct sessions from the log into summarized trips."""
    sessions: dict[str, list[dict]] = {}
    try:
        with open(log_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                ev = json.loads(line)
                sid = ev.get("session_id", "default")
                sessions.setdefault(sid, []).append(ev)
    except FileNotFoundError:
        return []

    history = []
    for sid, evs in sessions.items():
        attentions = [e.get("attention", 0.0) for e in evs if e.get("type") == "frame"]
        alerts = [e.get("alert") for e in evs if e.get("type") == "alert"]
        ts_list = [e.get("ts", 0.0) for e in evs if "ts" in e]
        start_ts = min(ts_list) if ts_list else 0.0
        end_ts = max(ts_list) if ts_list else 0.0
        dur = max(0.0, end_ts - start_ts)
        avg_att = sum(attentions) / len(attentions) if attentions else 100.0
        history.append({
            "session_id": sid,
            "started_at": start_ts,
            "duration_s": dur,
            "avg_attention": round(avg_att, 1),
            "alert_count": len(alerts),
            "safety_score": round(compute_safety_score(avg_att, len(alerts))),
        })
    history.sort(key=lambda x: x["started_at"], reverse=True)
    return history[:limit]


def PrintSummary(summary: dict) -> None:
    print("── Trip Summary ─────────────────────────────")
    print(f"Duration:      {summary['duration']:.0f}s")
    att_avg = summary.get('attention_avg')
    att_min = summary.get('attention_min')
    print(f"Attention avg: {att_avg:.0f if att_avg is not None else 0}  min: {att_min:.0f if att_min is not None else 0}")
    p_max = summary.get('perclos_max')
    print(f"PERCLOS max:   {p_max:.0% if p_max is not None else 0}")
    print(f"Alerts:        {summary['alert_count']}  {summary['alerts_by_type']}")


def WriteReport(summary: dict, out_path: str) -> None:
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("# Trip Report\n\n")
        for k, v in summary.items():
            f.write(f"- **{k}:** {v}\n")
