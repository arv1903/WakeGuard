"""
Driver Drowsiness & Distraction Detection — Head-Pose Estimation.

Uses MediaPipe Face Landmarker + OpenCV solvePnP to extract
pitch / yaw / roll Euler angles from a single face.
"""

import cv2
import numpy as np

from .config import (
    LandmarkIndices,
    FaceModelPoints,
)


def ComputeHeadPose(LandmarkerResult, FrameShape):
    """Estimate head orientation from MediaPipe face landmarks.

    Args:
        LandmarkerResult: MediaPipe FaceLandmarkerResult (or None).
        FrameShape (tuple): (height, width) of the source frame.

    Returns:
        dict with keys pitch, yaw, roll, valid, rvec, tvec, nose_pt.
    """
    empty = {
        "pitch": 0.0,
        "yaw": 0.0,
        "roll": 0.0,
        "valid": False,
        "rvec": None,
        "tvec": None,
        "nose_pt": None,
    }

    if LandmarkerResult is None or not LandmarkerResult.face_landmarks:
        return empty

    h, w = FrameShape[:2]
    face_lms = LandmarkerResult.face_landmarks[0]

    # Project landmark coordinates into pixel space
    img_pts = np.array(
        [[face_lms[i].x * w, face_lms[i].y * h] for i in LandmarkIndices],
        dtype=np.float64,
    )

    focal = w * 1.05
    cam_matrix = np.array(
        [[focal, 0, w / 2.0], [0, focal, h / 2.0], [0, 0, 1]],
        dtype=np.float64,
    )
    dist_coeffs = np.zeros((4, 1), dtype=np.float64)

    model_pts = np.array(FaceModelPoints, dtype=np.float64)

    success, rvec, tvec = cv2.solvePnP(
        model_pts, img_pts, cam_matrix, dist_coeffs,
        flags=cv2.SOLVEPNP_EPNP,
    )
    if not success:
        return empty

    rmat, _ = cv2.Rodrigues(rvec)
    euler_angles, _, _, _, _, _ = cv2.RQDecomp3x3(rmat)
    pitch, yaw, roll = euler_angles[0], euler_angles[1], euler_angles[2]

    return {
        "pitch": pitch,
        "yaw": yaw,
        "roll": roll,
        "valid": True,
        "rvec": rvec,
        "tvec": tvec,
        "nose_pt": img_pts[0],
    }
