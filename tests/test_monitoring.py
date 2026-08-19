import threading

from yolo.monitoring import (
    SNAPSHOT_SCHEMA_VERSION,
    MonitoringSnapshot,
    MonitoringStore,
)


def test_snapshot_is_json_safe_and_versioned():
    snapshot = MonitoringSnapshot(
        sequence=7,
        timestamp=123.4,
        trip_active=True,
        attention=72.5,
        ear=0.18,
        alert="MICROSLEEP - EYES CLOSED! WAKE UP!",
        alert_severity=4,
    )

    payload = snapshot.to_dict()

    assert payload["schema_version"] == SNAPSHOT_SCHEMA_VERSION
    assert payload["sequence"] == 7
    assert payload["trip_active"] is True
    assert payload["ear"] == 0.18
    assert payload["alert_severity"] == 4


def test_store_keeps_only_latest_snapshot():
    store = MonitoringStore(MonitoringSnapshot(sequence=1))
    store.publish(MonitoringSnapshot(sequence=2, attention=80.0))
    store.publish(MonitoringSnapshot(sequence=3, attention=60.0))

    assert store.latest().sequence == 3
    assert store.latest().attention == 60.0


def test_store_waits_for_a_newer_sequence():
    store = MonitoringStore(MonitoringSnapshot(sequence=1))
    updated = MonitoringSnapshot(sequence=2, attention=88.0)

    def publish_later():
        store.publish(updated)

    thread = threading.Thread(target=publish_later)
    thread.start()
    result = store.wait_for_update(after_sequence=1, timeout=1.0)
    thread.join()

    assert result == updated


def test_store_timeout_returns_current_snapshot():
    store = MonitoringStore(MonitoringSnapshot(sequence=4))

    result = store.wait_for_update(after_sequence=4, timeout=0.001)

    assert result.sequence == 4


def test_store_reveals_sequence_reset_after_backend_restart():
    store = MonitoringStore(MonitoringSnapshot(sequence=1))
    store.publish(MonitoringSnapshot(sequence=2))

    # A restarted backend begins at a lower sequence; clients must not wait
    # forever for a number that the new process can never reach.
    store.publish(MonitoringSnapshot(sequence=1, attention=55.0))
    result = store.wait_for_update(after_sequence=2, timeout=0.001)

    assert result.sequence == 1
    assert result.attention == 55.0
