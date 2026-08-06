"""Evaluate alert precision/recall against labeled drowsy periods.

Usage:
    python scripts/replay_eval.py --source testdata/sample.mp4 \\
        --labels testdata/labels.jsonl
Label format (one JSON object per line):
    {"start": 12.5, "end": 20.0, "label": "drowsy"}
Runs the pipeline headless, then compares fired alert times to labels.
"""

import argparse
import json
import os
import subprocess
import sys

# Running `python scripts/replay_eval.py` puts only scripts/ on sys.path;
# make the project root importable so `import yolo` works.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from yolo.eval import evaluate, load_alerts, parse_labels


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True)
    ap.add_argument("--labels", required=True)
    ap.add_argument("--log", default="logs/eval_session.jsonl")
    args = ap.parse_args()

    subprocess.run([sys.executable, "main.py", "--source", args.source,
                    "--headless", "--no-telegram", "--no-alarm", "--log", args.log],
                   check=True)
    alerts = load_alerts(args.log)
    result = evaluate(alerts, parse_labels(args.labels))
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
