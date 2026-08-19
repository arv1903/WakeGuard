import time

import pytest

from yolo.pairing import PairingManager, PairingRateLimitedError


def test_pairing_code_is_single_use_and_issues_token():
    manager = PairingManager(code_ttl=10, token_ttl=10)
    now = time.time()
    details = manager.details(now=now)

    issued = manager.exchange(details["code"], now=now + 0.5)

    assert issued["token_type"] == "Bearer"
    assert manager.is_valid_token(issued["access_token"], now=now + 0.5)
    with pytest.raises(ValueError, match="invalid pairing code"):
        manager.exchange(details["code"], now=now + 0.5)


def test_pairing_code_and_token_expire():
    manager = PairingManager(code_ttl=1, token_ttl=1)
    now = time.time()
    details = manager.details(now=now)

    with pytest.raises(ValueError, match="expired"):
        manager.exchange(details["code"], now=now + 1.1)

    fresh = manager.details(now=now + 1.1)
    issued = manager.exchange(fresh["code"], now=now + 1.2)
    assert manager.is_valid_token(issued["access_token"], now=now + 2.3) is False


def test_invalid_pairing_code_is_rejected():
    manager = PairingManager()
    with pytest.raises(ValueError, match="invalid pairing code"):
        manager.exchange("NOT-VALID")


def test_issued_token_can_be_revoked():
    manager = PairingManager()
    now = time.time()
    issued = manager.exchange(manager.details(now=now)["code"], now=now)
    token = issued["access_token"]

    assert manager.is_valid_token(token, now=now) is True
    assert manager.revoke_token(token) is True
    assert manager.is_valid_token(token, now=now) is False
    assert manager.revoke_token(token) is False


def test_failed_pairing_attempts_are_temporarily_throttled():
    manager = PairingManager(
        max_failed_attempts=2,
        failure_window=10,
        lockout_seconds=5,
    )
    now = 100.0

    with pytest.raises(ValueError, match="invalid pairing code"):
        manager.exchange("WRONG", now=now)
    with pytest.raises(PairingRateLimitedError) as exc:
        manager.exchange("WRONG", now=now + 1)
    assert exc.value.retry_after == 5

    with pytest.raises(PairingRateLimitedError):
        manager.exchange("WRONG", now=now + 2)

    details = manager.details(now=now + 6)
    issued = manager.exchange(details["code"], now=now + 6)
    assert manager.is_valid_token(issued["access_token"], now=now + 6)
