"""Minimal ``.env`` loader — no external dependency.

``python-dotenv`` is not installed in the target environments, so this tiny
loader covers the common syntax: blank lines, ``#`` comments, an optional
``export `` prefix, and optionally-quoted values. Existing environment
variables are never overridden (same default behaviour as python-dotenv).
"""

import os


def LoadEnvFile(path=".env") -> None:
    """Load ``KEY=VALUE`` pairs from *path* into ``os.environ``.

    Lines that are blank, start with ``#``, or contain no ``=`` are
    skipped. Values wrapped in matching single or double quotes have the
    quotes stripped. Variables already present in the environment are left
    untouched, so real OS-level settings always win over the file.

    Args:
        path (str): Path to the dotenv file. Missing files are a no-op.
    """
    if not os.path.exists(path):
        return
    with open(path, encoding="utf-8-sig") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            if line.startswith("export "):
                line = line[7:].strip()
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            if key and key not in os.environ:
                os.environ[key] = value
