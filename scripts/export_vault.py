#!/usr/bin/env python3
"""Export Freebuff conversation threads from the local DB into the Obsidian vault.

Reads ``.freebuff/desktop-v2.db`` and writes one Markdown transcript per thread
that has messages into ``notes/transcripts/`` (a junction into the Obsidian
vault's ``Freebuff`` folder). Only user + assistant *text* parts are exported;
reasoning, tool calls, agent (subagent) blocks, ads, and change summaries are
skipped, per the vault-export convention.

Idempotent: existing transcript files are never overwritten, so re-running
only adds what is missing.

Usage:
    python scripts/export_vault.py [--db PATH] [--out DIR]
"""

import argparse
import json
import os
import sqlite3
from datetime import datetime, timezone

# Placeholder title the desktop app writes for threads whose title was never
# derived from a real prompt.
PLACEHOLDER_TITLES = {"New thread", ""}

# Roles whose parts are transcribed.
INCLUDE_ROLES = {"user", "assistant"}

# Part kinds that carry user-visible text.
TEXT_KINDS = {"text"}

# Part kinds explicitly excluded from the transcript.
SKIP_KINDS = {"reasoning", "tool", "agent", "changes", "ad"}


def iso(ms):
    """Millisecond epoch -> ISO-8601 UTC string."""
    if ms is None:
        return None
    return datetime.fromtimestamp(ms / 1000.0, tz=timezone.utc).isoformat()


def title_for(thread, first_user_text):
    """Prefer the DB title; fall back to / complete it from the first user message."""
    raw = (thread["title"] or "").strip()
    if raw in PLACEHOLDER_TITLES:
        return _derive(first_user_text)
    # DB titles are truncated to ~60 chars by the app; if it ends mid-sentence
    # without punctuation, complete it from the first user message.
    if len(raw) >= 40 and not raw.rstrip().endswith((".", "!", "?", ":", "…")):
        return _derive(first_user_text)
    return raw


def _derive(first_user_text):
    if not first_user_text:
        return "Untitled thread"
    first_line = first_user_text.strip().splitlines()[0].strip()
    return first_line[:120] or "Untitled thread"


def text_of(parts_json):
    """Join all text parts of a message. Returns '' if none."""
    try:
        parts = json.loads(parts_json)
    except (TypeError, ValueError):
        return ""
    chunks = []
    for part in parts:
        if not isinstance(part, dict):
            continue
        kind = part.get("kind")
        if kind in SKIP_KINDS:
            continue
        if kind in TEXT_KINDS:
            text = part.get("text")
            if text:
                chunks.append(text)
    return "\n\n".join(chunks).strip()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--db", default=os.path.join(".freebuff", "desktop-v2.db"))
    ap.add_argument("--out", default=os.path.join("notes", "transcripts"))
    args = ap.parse_args()

    if not os.path.exists(args.db):
        raise SystemExit(f"database not found: {args.db}")

    con = sqlite3.connect(args.db)
    con.row_factory = sqlite3.Row

    threads = con.execute(
        "SELECT * FROM threads ORDER BY created_at"
    ).fetchall()
    messages = {}
    for row in con.execute(
        "SELECT * FROM messages ORDER BY ts, seq"
    ):
        messages.setdefault(row["thread_id"], []).append(row)

    os.makedirs(args.out, exist_ok=True)

    exported = 0
    skipped_no_messages = 0
    skipped_existing = 0
    for t in threads:
        msgs = messages.get(t["id"], [])
        if not msgs:
            skipped_no_messages += 1
            continue

        path = os.path.join(args.out, f"{t['id']}.md")
        if os.path.exists(path):
            skipped_existing += 1
            print(f"exists:  {path}")
            continue

        # First user text (for title fallback) and transcript body.
        body_lines = []
        first_user_text = ""
        message_count = 0
        for m in msgs:
            if m["role"] not in INCLUDE_ROLES:
                continue
            text = text_of(m["parts_json"])
            if not text:
                continue
            if m["role"] == "user" and not first_user_text:
                first_user_text = text
            message_count += 1
            body_lines.append(
                f"## {m['role']} — {iso(m['ts'])}\n\n{text}"
            )

        if message_count == 0:
            skipped_no_messages += 1
            continue

        title = title_for(t, first_user_text)
        base = os.path.splitext(os.path.basename(path))[0]
        frontmatter = "\n".join(
            [
                "---",
                f"title: {json.dumps(title, ensure_ascii=False)}",
                f"thread_id: {t['id']}",
                f"model: {json.dumps(t['model'] or 'unknown')}",
                f"created: {iso(t['created_at'])}",
                f"updated: {iso(t['updated_at'])}",
                f"message_count: {message_count}",
                f"status: {t['status']}",
                f"project: {json.dumps(t['project_path'])}",
                "---",
            ]
        )
        content = (
            f"{frontmatter}\n\n"
            f"# {title}\n\n"
            f"> Summary: [[../{base}]]\n\n"
            f"---\n\n"
            f"{chr(10).join(body_lines)}\n"
        )
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)

        exported += 1
        print(f"wrote:   {path} ({message_count} messages)")

    print(
        f"\nDone: {exported} exported, {skipped_existing} already existed, "
        f"{skipped_no_messages} threads skipped (no text messages)."
    )


if __name__ == "__main__":
    main()
