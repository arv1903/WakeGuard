import queue

from yolo import telegram


def test_trigger_disabled_does_not_enqueue():
    telegram.SetTelegramEnabled(False)
    telegram._Queue.queue.clear()
    telegram.TriggerTelegramPhoto(object())
    assert telegram._Queue.empty()


def test_trigger_enabled_enqueues():
    telegram.SetTelegramEnabled(True)
    telegram._Queue.queue.clear()
    telegram.TriggerTelegramPhoto(object(), Cooldown=1.0)
    assert telegram._Queue.qsize() == 1
    assert telegram._Queue.get_nowait() is not None
