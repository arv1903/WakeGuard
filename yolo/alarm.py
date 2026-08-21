"""
Driver Drowsiness & Distraction Detection — Audio Alarm.

Uses Windows MCI for looping MP3 playback.
Adapt for Linux/macOS by replacing with playsound / pygame.
"""

import ctypes
import os
import sys

_IsPlayingAlarm = False
_IsMuted = False


def _get_sound_path() -> str:
    candidates = [
        "alert.mp3",
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "alert.mp3"),
    ]
    for c in candidates:
        if os.path.exists(c):
            return os.path.abspath(c)
    return "alert.mp3"


def SetAlarmMuted(muted: bool) -> None:
    """Mute/unmute the alarm. Muting stops any active playback."""
    global _IsMuted
    _IsMuted = muted
    if muted:
        UpdateAlarm(False)


def UpdateAlarm(Active):
    """Start or stop the looping alarm sound.

    Args:
        Active (bool): True to start, False to stop.
    """
    global _IsPlayingAlarm

    if _IsMuted:
        return

    if sys.platform != "win32":
        # Non-Windows stub: audio alarm is skipped cleanly without crashing.
        _IsPlayingAlarm = bool(Active)
        return

    sound_path = _get_sound_path()

    if Active and not _IsPlayingAlarm:
        try:
            ctypes.windll.winmm.mciSendStringW("close alarm", None, 0, None)
            ctypes.windll.winmm.mciSendStringW(
                f'open "{sound_path}" alias alarm', None, 0, None
            )
            ctypes.windll.winmm.mciSendStringW("play alarm repeat", None, 0, None)
            _IsPlayingAlarm = True
        except Exception:
            _IsPlayingAlarm = False

    elif not Active and _IsPlayingAlarm:
        try:
            ctypes.windll.winmm.mciSendStringW("stop alarm", None, 0, None)
            ctypes.windll.winmm.mciSendStringW("close alarm", None, 0, None)
        except Exception:
            pass
        _IsPlayingAlarm = False
