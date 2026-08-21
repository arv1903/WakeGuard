import re

import numpy as np

from yolo import telegram


def test_trigger_disabled_does_not_enqueue():
    telegram.SetTelegramEnabled(False)
    telegram._Queue.queue.clear()
    telegram.TriggerTelegramPhoto(object())
    assert telegram._Queue.empty()


def test_trigger_enabled_enqueues_image_and_message():
    telegram.SetTelegramEnabled(True)
    telegram._Queue.queue.clear()
    telegram.TriggerTelegramPhoto("img", Message="ALERT!", Cooldown=1.0)
    assert telegram._Queue.qsize() == 1
    item = telegram._Queue.get_nowait()
    # New 3-tuple (image, message, cooldown) for per-call cooldown fix
    image, message = item[0], item[1]
    assert image == "img"
    assert message == "ALERT!"
    assert item[2] == 1.0


def test_build_caption_includes_time_and_location():
    caption = telegram._BuildCaption(
        "ALERT!", {"lat": -6.2088, "lon": 106.8456, "name": "Jakarta, Indonesia"})
    assert "ALERT!" in caption
    assert "Jakarta, Indonesia" in caption
    assert "-6.2088, 106.8456" in caption
    assert re.search(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}", caption)


def test_build_caption_without_location_only_has_time():
    caption = telegram._BuildCaption("ALERT!", None)
    assert "ALERT!" in caption
    assert "📍" not in caption


def test_get_location_uses_env_override(monkeypatch):
    monkeypatch.setenv("DRIVER_LOCATION_LAT", "-6.2088")
    monkeypatch.setenv("DRIVER_LOCATION_LON", "106.8456")
    monkeypatch.setenv("DRIVER_LOCATION_NAME", "Test City")
    telegram._LocationCache.update(ts=0.0, data=None)
    loc = telegram.GetApproxLocation()
    assert loc == {"lat": -6.2088, "lon": 106.8456, "name": "Test City"}


def test_get_location_ip_geolocation_fallback(monkeypatch):
    class FakeResp:
        def json(self):
            return {"status": "success", "lat": -6.2088, "lon": 106.8456,
                    "city": "Jakarta", "regionName": "Jakarta",
                    "country": "Indonesia"}

    monkeypatch.delenv("DRIVER_LOCATION_LAT", raising=False)
    monkeypatch.delenv("DRIVER_LOCATION_LON", raising=False)
    monkeypatch.setattr(telegram.requests, "get", lambda *a, **k: FakeResp())
    telegram._LocationCache.update(ts=0.0, data=None)
    loc = telegram.GetApproxLocation()
    assert loc["lat"] == -6.2088
    assert loc["name"] == "Jakarta, Jakarta, Indonesia"


def test_get_location_ip_geolocation_failure_returns_none(monkeypatch):
    def boom(*a, **k):
        raise telegram.requests.RequestException("no network")

    monkeypatch.delenv("DRIVER_LOCATION_LAT", raising=False)
    monkeypatch.delenv("DRIVER_LOCATION_LON", raising=False)
    monkeypatch.setattr(telegram.requests, "get", boom)
    telegram._LocationCache.update(ts=0.0, data=None)
    assert telegram.GetApproxLocation() is None


def test_send_photo_posts_full_frame_with_caption(monkeypatch):
    monkeypatch.setenv("TELEGRAM_BOT_TOKEN", "tok")
    monkeypatch.setenv("TELEGRAM_CHAT_ID", "123")
    calls = []

    class FakeResp:
        pass

    def fake_post(url, **kwargs):
        calls.append((url, kwargs))
        return FakeResp()

    monkeypatch.setattr(telegram.requests, "post", fake_post)
    frame = np.zeros((50, 80, 3), dtype=np.uint8)
    telegram._SendPhoto(frame, "CAPTION")
    assert len(calls) == 1
    url, kwargs = calls[0]
    assert url.endswith("/sendPhoto")
    assert kwargs["data"]["caption"] == "CAPTION"
    assert kwargs["files"]["photo"][2] == "image/jpeg"


def test_send_location_posts_coordinates(monkeypatch):
    monkeypatch.setenv("TELEGRAM_BOT_TOKEN", "tok")
    monkeypatch.setenv("TELEGRAM_CHAT_ID", "123")
    calls = []

    class FakeResp:
        pass

    def fake_post(url, **kwargs):
        calls.append((url, kwargs))
        return FakeResp()

    monkeypatch.setattr(telegram.requests, "post", fake_post)
    telegram._SendLocation("tok", "123", {"lat": -6.2, "lon": 106.8})
    assert len(calls) == 1
    url, kwargs = calls[0]
    assert url.endswith("/sendLocation")
    assert kwargs["data"] == {"chat_id": "123", "latitude": -6.2,
                              "longitude": 106.8}
