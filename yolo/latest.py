"""Thread-safe handoff that keeps only the newest item (drop-old semantics)."""
import threading


class LatestValue:
    """Holds the single most recent value published by a producer thread.

    Consumers read via `latest()` or block via `wait_for_new()`. Slow
    consumers simply see the newest value and intermediate ones are dropped —
    the pipeline never blocks.

    Uses a Condition to avoid 200 wakes/s spin-poll (`sleep(0.005)`) that
    burned ~8% CPU in the original pipeline.
    """

    def __init__(self):
        self._cond = threading.Condition(threading.Lock())
        self._value = None
        self._version = 0

    def publish(self, value) -> None:
        with self._cond:
            self._value = value
            self._version += 1
            self._cond.notify_all()

    def latest(self):
        with self._cond:
            return self._value

    def wait_for_new(self, last_version: int, timeout: float | None = None) -> tuple[object | None, int]:
        """Block until a newer value is published or timeout.

        Returns (value, new_version). If timeout, value is current value.
        """
        with self._cond:
            ok = self._cond.wait_for(lambda: self._version > last_version, timeout=timeout)
            if not ok:
                return None, self._version
            return self._value, self._version

    @property
    def version(self) -> int:
        with self._cond:
            return self._version
