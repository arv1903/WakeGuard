"""Trip summary computed from a session log or Supabase database."""

from __future__ import annotations

import json
from collections import Counter
from typing import Any

from .score import compute_safety_score


# ---------------------------------------------------------------------------
# File-based implementations (original, always available)
# ---------------------------------------------------------------------------

def _build_summary_from_file(log_path: str, session_id: str | None = None) -> dict:
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
                    alerts.append(ev["alert"])
                    alert_times.append(ts)
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


def _build_summary_from_db(db: Any, session_id: str) -> dict:
    """Build summary from Supabase. Prefers pre-computed stats in sessions
    table; falls back to telemetry + alert_events queries."""
    # Try pre-computed stats first (written by JsonlTailReader on session stop)
    try:
        sess_resp = (
            db.table("sessions")
            .select("duration_s,avg_attention,avg_perclos,alert_count,safety_score,alerts_by_type")
            .eq("id", session_id)
            .execute()
        )
        sess = (sess_resp.data or [{}])[0]
        if sess.get("duration_s") is not None:
            alerts_by_type = {}
            raw = sess.get("alerts_by_type")
            if isinstance(raw, str):
                try:
                    import json as _json
                    alerts_by_type = _json.loads(raw)
                except Exception:
                    pass
            elif isinstance(raw, dict):
                alerts_by_type = raw
            return {
                "duration": sess.get("duration_s") or 0.0,
                "trip_duration_s": sess.get("duration_s") or 0.0,
                "attention_min": None,
                "attention_avg": sess.get("avg_attention"),
                "avg_attention": sess.get("avg_attention") or 0.0,
                "perclos_max": sess.get("avg_perclos"),
                "max_perclos": sess.get("avg_perclos") or 0.0,
                "alert_count": sess.get("alert_count") or 0,
                "avg_blinks_per_min": 0.0,
                "alerts_by_type": alerts_by_type,
                "alert_times": [],
            }
    except Exception:
        pass

    # Fallback: compute from raw telemetry + alert_events
    try:
        tele_resp = (
            db.table("telemetry")
            .select("attention,perclos,blinks_per_min")
            .eq("session_id", session_id)
            .order("ts")
            .execute()
        )
        frames = tele_resp.data or []
    except Exception:
        frames = []

    try:
        alert_resp = (
            db.table("alert_events")
            .select("alert,ts")
            .eq("session_id", session_id)
            .eq("event_type", "alert")
            .order("ts")
            .execute()
        )
        alert_rows = alert_resp.data or []
    except Exception:
        alert_rows = []

    attentions = [f.get("attention", 0.0) for f in frames if f.get("attention") is not None]
    perclos_vals = [f.get("perclos", 0.0) for f in frames if f.get("perclos") is not None]
    blinks = [f.get("blinks_per_min", 0.0) for f in frames if f.get("blinks_per_min") is not None]

    att_min = min(attentions) if attentions else None
    att_avg = (sum(attentions) / len(attentions)) if attentions else None
    p_max = max(perclos_vals) if perclos_vals else None
    blink_avg = (sum(blinks) / len(blinks)) if blinks else 0.0

    # Duration from session row if available, else from frame count (1 Hz)
    duration = float(len(frames))  # approximate from telemetry count

    return {
        "duration": duration,
        "trip_duration_s": duration,
        "attention_min": att_min,
        "attention_avg": att_avg,
        "avg_attention": att_avg if att_avg is not None else 0.0,
        "perclos_max": p_max,
        "max_perclos": p_max if p_max is not None else 0.0,
        "alert_count": len(alert_rows),
        "avg_blinks_per_min": blink_avg,
        "alerts_by_type": dict(Counter(a["alert"] for a in alert_rows)),
        "alert_times": [],
    }


def _build_history_from_file(log_path: str, limit: int = 10) -> list[dict]:
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


def _build_history_from_db(db: Any, user_id: str, limit: int = 10) -> list[dict]:
    """Query the ``sessions`` table for this user's recent trips."""
    try:
        resp = (
            db.table("sessions")
            .select("id,started_at,duration_s,avg_attention,alert_count,safety_score")
            .eq("user_id", user_id)
            .order("started_at", desc=True)
            .limit(limit)
            .execute()
        )
        rows = resp.data or []
    except Exception:
        return []

    history = []
    for row in rows:
        history.append({
            "session_id": row["id"],
            "started_at": _parse_ts(row.get("started_at")),
            "duration_s": row.get("duration_s") or 0.0,
            "avg_attention": round(row.get("avg_attention") or 100.0, 1),
            "alert_count": row.get("alert_count") or 0,
            "safety_score": round(row.get("safety_score") or compute_safety_score(
                row.get("avg_attention") or 100.0, row.get("alert_count") or 0
            )),
        })
    return history


def _build_telemetry_from_file(log_path: str, session_id: str, limit: int = 600) -> list[dict]:
    frames: list[dict] = []
    try:
        with open(log_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                ev = json.loads(line)
                if ev.get("session_id") != session_id:
                    continue
                if ev.get("type") != "frame":
                    continue
                frames.append(ev)
    except FileNotFoundError:
        return []

    if not frames:
        return []

    start_ts = frames[0].get("ts", 0.0)
    result = []
    for ev in frames[-limit:]:
        result.append({
            "ts": round(ev.get("ts", 0.0) - start_ts, 2),
            "attention": ev.get("attention", 0.0),
            "perclos": ev.get("perclos", 0.0),
        })
    return result


def _build_telemetry_from_db(db: Any, session_id: str, limit: int = 600) -> list[dict]:
    """Query the ``telemetry`` table for a single session's data points."""
    try:
        resp = (
            db.table("telemetry")
            .select("ts,attention,perclos")
            .eq("session_id", session_id)
            .order("ts")
            .limit(limit)
            .execute()
        )
        rows = resp.data or []
    except Exception:
        return []

    if not rows:
        return []

    # Compute relative timestamps from the first row
    start = _parse_ts(rows[0].get("ts"))
    result = []
    for row in rows:
        result.append({
            "ts": round(_parse_ts(row.get("ts")) - start, 2),
            "attention": row.get("attention", 0.0),
            "perclos": row.get("perclos", 0.0),
        })
    return result


def _parse_ts(value: Any) -> float:
    """Parse a timestamp that might be a unix float or an ISO string."""
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            from datetime import datetime, timezone
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return dt.timestamp()
        except Exception:
            return 0.0
    return 0.0


# ---------------------------------------------------------------------------
# Public API — tries DB first when db_client is provided, falls back to file
# ---------------------------------------------------------------------------

def BuildSummary(
    log_path: str,
    session_id: str | None = None,
    db_client: Any | None = None,
    user_id: str | None = None,
) -> dict:
    if db_client is not None and session_id is not None:
        try:
            return _build_summary_from_db(db_client, session_id)
        except Exception:
            pass  # fall through to file
    return _build_summary_from_file(log_path, session_id)


def BuildSessionHistory(
    log_path: str,
    limit: int = 10,
    db_client: Any | None = None,
    user_id: str | None = None,
) -> list[dict]:
    if db_client is not None and user_id is not None:
        try:
            return _build_history_from_db(db_client, user_id, limit)
        except Exception:
            pass  # fall through to file
    return _build_history_from_file(log_path, limit)


def BuildSessionTelemetry(
    log_path: str,
    session_id: str,
    limit: int = 600,
    db_client: Any | None = None,
) -> list[dict]:
    if db_client is not None:
        try:
            return _build_telemetry_from_db(db_client, session_id, limit)
        except Exception:
            pass  # fall through to file
    return _build_telemetry_from_file(log_path, session_id, limit)


def PrintSummary(summary: dict) -> None:
    print("── Trip Summary ─────────────────────────────")
    print(f"Duration:      {summary['duration']:.0f}s")
    att_avg = summary.get('attention_avg')
    att_min = summary.get('attention_min')
    avg_str = f"{att_avg:.0f}" if att_avg is not None else "0"
    min_str = f"{att_min:.0f}" if att_min is not None else "0"
    print(f"Attention avg: {avg_str}  min: {min_str}")
    p_max = summary.get('perclos_max')
    perclos_str = f"{p_max:.0%}" if p_max is not None else "0"
    print(f"PERCLOS max:   {perclos_str}")
    print(f"Alerts:        {summary['alert_count']}  {summary['alerts_by_type']}")


def WriteReport(summary: dict, out_path: str) -> None:
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("# Trip Report\n\n")
        for k, v in summary.items():
            f.write(f"- **{k}:** {v}\n")
