from yolo import config


def test_alert_messages_cover_all_channels():
    expected = {"combined", "face_lost", "head_away", "low_blink", "yolo",
                "perclos", "microsleep"}
    assert set(config.AlertMessages.keys()) == expected


def test_threshold_sanity():
    assert 0.0 < config.YoloDrowsyWeak < config.YoloDrowsyThreshold <= 1.0
    assert config.AttentionFocusedMin > config.AttentionUnfocusedMin
    assert config.HeadDownTime > 0.0 and config.HeadAwayTime > 0.0
    assert config.FrameWidth >= config.HudPanel > 0
