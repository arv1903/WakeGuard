"""
Driver Drowsiness & Distraction Detection — Model Initialisation.

Sets up YOLO for eye-state classification and MediaPipe Face Landmarker
for head-pose estimation.
"""

from ultralytics import YOLO
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision


def CreateDetectionModel(ModelPath="best.pt"):
    """Load the YOLO eye-state detection model.

    Args:
        ModelPath (str): Path to the .pt weights file.

    Returns:
        YOLO model instance.
    """
    return YOLO(ModelPath)


def CreateFaceLandmarker(ModelPath="face_landmarker.task"):
    """Create a MediaPipe FaceLandmarker for video-mode head-pose estimation.

    Args:
        ModelPath (str): Path to the .task model file.

    Returns:
        FaceLandmarker instance.
    """
    base = mp_python.BaseOptions(model_asset_path=ModelPath)
    opts = vision.FaceLandmarkerOptions(
        base_options=base,
        running_mode=vision.RunningMode.VIDEO,
        num_faces=1,
        min_face_detection_confidence=0.5,
        min_tracking_confidence=0.5,
        output_face_blendshapes=False,
        output_facial_transformation_matrixes=False,
    )
    return vision.FaceLandmarker.create_from_options(opts)
