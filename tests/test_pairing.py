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


def _pair(manager: PairingManager) -> str:
    code = manager.details()["code"]
    return manager.exchange(code)["access_token"]


def test_issued_tokens_carry_device_label_and_expiry():
    manager = PairingManager()
    token = _pair(manager)

    tokens = manager.list_tokens()
    assert len(tokens) == 1
    record = tokens[0]
    assert record["token_preview"] == token[:8]
    assert record["device_name"] == ""
    assert record["issued_at"] == pytest.approx(time.time(), abs=5)
    assert record["expires_at"] == pytest.approx(
        time.time() + 24 * 60 * 60, abs=5
    )


def test_list_tokens_is_admin_only_shape_and_never_returns_secrets():
    manager = PairingManager()
    _pair(manager)
    _pair(manager)

    tokens = manager.list_tokens()
    assert len(tokens) == 2
    for record in tokens:
        assert set(record.keys()) == {
            "token_preview",
            "device_name",
            "issued_at",
            "expires_at",
        }
        # A preview must not be usable as a token.
        assert len(record["token_preview"]) < 16
        assert "access_token" not in record


def test_exchange_accepts_optional_device_name_label():
    manager = PairingManager()
    code = manager.details()["code"]
    manager.exchange(code, device_name="Marvin's Phone")

    tokens = manager.list_tokens()
    assert len(tokens) == 1
    assert tokens[0]["device_name"] == "Marvin's Phone"


def test_admin_revoke_removes_token_but_others_keep_working():
    manager = PairingManager()
    token_a = _pair(manager)
    token_b = _pair(manager)

    assert manager.revoke_admin(token_a) is True
    assert manager.revoke_admin(token_a) is False  # already gone
    assert manager.is_valid_token(token_a) is False
    assert manager.is_valid_token(token_b) is True


def test_expired_tokens_drop_out_of_listing():
    manager = PairingManager(code_ttl=10, token_ttl=0.05)
    token = _pair(manager)
    assert len(manager.list_tokens()) == 1

    time.sleep(0.08)
    assert manager.list_tokens() == []
    assert manager.is_valid_token(token) is False
