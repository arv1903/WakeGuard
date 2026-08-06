"""Thread-safe handoff that keeps only the newest item (drop-old semantics)."""
import threading


class LatestValue:
    """Holds the single most recent value published by a producer thread.

    Consumers read via `latest()`; slow consumers simply see the newest
    value and intermediate ones are dropped — the pipeline never blocks.
    """

    def __init__(self):
        self._lock = threading.Lock()
        self._value = None

    def publish(self, value) -> None:
        with self._lock:
            self._value = value

    def latest(self):
        with self._lock:
            return self._value
