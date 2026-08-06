"""
Driver Drowsiness & Distraction Detection — Audio Alarm.

Uses Windows MCI for looping MP3 playback.
Adapt for Linux/macOS by replacing with playsound / pygame.
"""

import ctypes

_IsPlayingAlarm = False
_IsMuted = False


def SetAlarmMuted(muted: bool) -> None:
    """Mute/unmute the alarm. Muting stops any active playback."""
    global _IsMuted
    _IsMuted = muted
    if muted:
        UpdateAlarm(False)


def IsAlarmMuted() -> bool:
    return _IsMuted


def UpdateAlarm(Active):
    """Start or stop the looping alarm sound.

    Args:
        Active (bool): True to start, False to stop.
    """
    global _IsPlayingAlarm

    if _IsMuted:
        return

    if Active and not _IsPlayingAlarm:
        ctypes.windll.winmm.mciSendStringW("close alarm", None, 0, None)
        ctypes.windll.winmm.mciSendStringW(
            'open "alert.mp3" alias alarm', None, 0, None
        )
        ctypes.windll.winmm.mciSendStringW("play alarm repeat", None, 0, None)
        _IsPlayingAlarm = True

    elif not Active and _IsPlayingAlarm:
        ctypes.windll.winmm.mciSendStringW("stop alarm", None, 0, None)
        ctypes.windll.winmm.mciSendStringW("close alarm", None, 0, None)
        _IsPlayingAlarm = False
