#!/usr/bin/env python3
"""Migrate existing JSONL session logs to Supabase.

Usage:
    python scripts/migrate_to_supabase.py --email user@example.com --password secret

Requires SUPABASE_URL and SUPABASE_SERVICE_KEY environment variables (or .env file).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from yolo.db import get_db, auth_register, auth_login
from yolo.score import compute_safety_score


def parse_args():
    ap = argparse.ArgumentParser(description="Migrate JSONL session logs to Supabase")
    ap.add_argument("--email", required=True, help="Account email")
    ap.add_argument("--password", required=True, help="Account password")
    ap.add_argument("--display-name", default="", help="Display name for the account")
    ap.add_argument("--log-path", default="logs/session.jsonl", help="Path to session log")
    ap.add_argument("--device-name", default="Migrated Device", help="Device name")
    ap.add_argument("--dry-run", action="store_true", help="Parse but don't write to DB")
    return ap.parse_args()


def parse_sessions(log_path: str) -> dict[str, list[dict]]:
    """Parse all sessions from a JSONL log file."""
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
        print(f"[error] Log file not found: {log_path}")
        return {}
    return sessions


def build_session_summary(events: list[dict]) -> dict:
    """Build a session summary from its events."""
    attentions = []
    perclos_vals = []
    blinks = []
    alerts = []
    alert_times = []

    for ev in events:
        ts = ev.get("ts", 0.0)
        if ev.get("type") == "frame":
            attentions.append(ev.get("attention", 0.0))
            perclos_vals.append(ev.get("perclos", 0.0))
            if "blinks_per_min" in ev:
                blinks.append(ev["blinks_per_min"])
        elif ev.get("type") == "alert":
            alerts.append(ev["alert"])
            alert_times.append(ts)

    ts_list = [e.get("ts", 0.0) for e in events if "ts" in e]
    start_ts = min(ts_list) if ts_list else 0.0
    end_ts = max(ts_list) if ts_list else 0.0
    duration = max(0.0, end_ts - start_ts)

    avg_att = sum(attentions) / len(attentions) if attentions else 100.0
    avg_perclos = sum(perclos_vals) / len(perclos_vals) if perclos_vals else 0.0

    return {
        "started_at": datetime.fromtimestamp(start_ts, tz=timezone.utc).isoformat(),
        "ended_at": datetime.fromtimestamp(end_ts, tz=timezone.utc).isoformat(),
        "duration_s": duration,
        "avg_attention": round(avg_att, 1),
        "avg_perclos": round(avg_perclos, 3),
        "alert_count": len(alerts),
        "safety_score": round(compute_safety_score(avg_att, len(alerts))),
        "alerts_by_type": dict(Counter(alerts)),
    }


def main():
    args = parse_args()

    db = get_db()
    if db is None:
        print("[error] Supabase not configured. Set SUPABASE_URL and SUPABASE_SERVICE_KEY.")
        sys.exit(1)

    # Parse sessions from log file
    print(f"[info] Parsing {args.log_path}...")
    sessions = parse_sessions(args.log_path)
    if not sessions:
        print("[info] No sessions found.")
        return

    print(f"[info] Found {len(sessions)} sessions with {sum(len(v) for v in sessions.values())} total events")

    if args.dry_run:
        print("[dry-run] Would create the following sessions:")
        for sid, events in sessions.items():
            summary = build_session_summary(events)
            print(f"  {sid[:12]}... duration={summary['duration_s']:.0f}s "
                  f"attention={summary['avg_attention']:.0f} alerts={summary['alert_count']}")
        return

    # Create or authenticate user
    print(f"[info] Authenticating as {args.email}...")
    login_result = auth_login(args.email, args.password)
    if login_result is None:
        print("[info] User doesn't exist, creating...")
        register_result = auth_register(args.email, args.password, args.display_name)
        if register_result is None:
            print("[error] Failed to create user.")
            sys.exit(1)
        login_result = auth_login(args.email, args.password)
        if login_result is None:
            print("[error] Failed to login after registration.")
            sys.exit(1)

    user_id = login_result["user_id"]
    print(f"[info] Authenticated as user {user_id}")

    # Create a device entry
    device_resp = (
        db.table("devices")
        .insert({
            "user_id": user_id,
            "device_name": args.device_name,
            "platform": "migrated",
        })
        .execute()
    )
    device_id = device_resp.data[0]["id"] if device_resp.data else None
    print(f"[info] Created device {device_id}")

    # Migrate each session
    for sid, events in sessions.items():
        summary = build_session_summary(events)

        # Create session row
        session_resp = (
            db.table("sessions")
            .insert({
                "id": sid,
                "device_id": device_id,
                "user_id": user_id,
                "started_at": summary["started_at"],
                "ended_at": summary["ended_at"],
                "duration_s": summary["duration_s"],
                "avg_attention": summary["avg_attention"],
                "avg_perclos": summary["avg_perclos"],
                "alert_count": summary["alert_count"],
                "safety_score": summary["safety_score"],
                "alerts_by_type": summary["alerts_by_type"],
            })
            .execute()
        )

        # Batch insert telemetry rows
        telemetry_rows = []
        for ev in events:
            if ev.get("type") == "frame":
                telemetry_rows.append({
                    "session_id": sid,
                    "ts": datetime.fromtimestamp(ev.get("ts", 0), tz=timezone.utc).isoformat(),
                    "attention": ev.get("attention"),
                    "perclos": ev.get("perclos"),
                    "ema_drowsy": ev.get("ema_drowsy"),
                    "pitch": ev.get("pitch"),
                    "yaw": ev.get("yaw"),
                    "roll": ev.get("roll"),
                    "pose_valid": ev.get("pose_valid"),
                    "alert": ev.get("alert"),
                    "blinks_per_min": ev.get("blinks_per_min"),
                })

        if telemetry_rows:
            # Supabase has a 1000-row limit per insert, chunk if needed
            chunk_size = 500
            for i in range(0, len(telemetry_rows), chunk_size):
                chunk = telemetry_rows[i:i + chunk_size]
                db.table("telemetry").insert(chunk).execute()

        # Insert alert events
        alert_rows = []
        for ev in events:
            if ev.get("type") in ("alert", "clear"):
                alert_rows.append({
                    "session_id": sid,
                    "ts": datetime.fromtimestamp(ev.get("ts", 0), tz=timezone.utc).isoformat(),
                    "alert": ev["alert"],
                    "event_type": ev["type"],
                    "fired_for": ev.get("fired_for"),
                })

        if alert_rows:
            db.table("alert_events").insert(alert_rows).execute()

        print(f"[ok] Session {sid[:12]}... migrated "
              f"({len(telemetry_rows)} telemetry, {len(alert_rows)} alerts)")

    print(f"\n[done] Migrated {len(sessions)} sessions to Supabase.")


if __name__ == "__main__":
    main()
