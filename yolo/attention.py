"""
Driver Drowsiness & Distraction Detection — Attention & Timer Logic.

Attention scoring, generic accumulator-based timer state machine,
and short helper utils.
"""

from .config import (
    AttentionYawWeight,
    AttentionPitchWeight,
    AttentionEyeWeight,
)


def ComputeAttentionScore(DrowsyConf, Pitch, Yaw):
    """Calculate a 0–100 attention score from eye-confidence and head angles.

    Args:
        DrowsyConf (float): YOLO drowsy confidence [0–1].
        Pitch (float): Head pitch angle (degrees, down = negative).
        Yaw (float): Head yaw angle (degrees).

    Returns:
        float: Attention score clamped to [0, 100].
    """
    score = 100.0

    yaw_penalty = min(abs(Yaw) / 45.0, 1.0) * AttentionYawWeight

    if Pitch < 0:
        pitch_penalty = min(abs(Pitch) / 30.0, 1.0) * AttentionPitchWeight
    else:
        pitch_penalty = 0.0

    eye_penalty = DrowsyConf * AttentionEyeWeight

    score -= yaw_penalty + pitch_penalty + eye_penalty
    return max(0.0, min(100.0, score))


def UpdateTimer(Condition, Accumulated, DeltaTime, RequiredDuration, Freeze=False):
    """Accumulator-based escalating timer with optional freeze.

    When *Freeze* is True the accumulated time is preserved unchanged,
    allowing timers to survive face-loss episodes without firing
    prematurely and without losing their progress.

    Args:
        Condition (bool): Whether the monitored condition is currently true.
        Accumulated (float): Seconds accumulated so far.
        DeltaTime (float): Wall-clock seconds since the previous frame.
        RequiredDuration (float): Seconds the condition must persist for.
        Freeze (bool): If True, pause accumulation (preserve current value).

    Returns:
        tuple: (NewAccumulated: float, Fired: bool)
    """
    if not Condition:
        return 0.0, False

    if Freeze:
        return Accumulated, False

    new_acc = Accumulated + DeltaTime
    return new_acc, new_acc >= RequiredDuration
