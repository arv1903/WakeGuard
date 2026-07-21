# 🚗 Driver Drowsiness & Distraction Detection

Real-time driver monitoring system that detects drowsiness and distraction using a **YOLO eye-state model** combined with **MediaPipe Face Mesh head-pose estimation**. Alerts the driver with an audible alarm and sends a photo to Telegram when risky behavior is detected.

---

## ✨ Features

| Feature | Description |
|---|---|
| **Eye-state detection** | YOLO model (`best.pt`) classifies eyes as **Drowsy** or **Alert** every frame |
| **Head-pose estimation** | MediaPipe Face Landmarker computes **pitch**, **yaw**, and **roll** Euler angles in real time |
| **Attention scoring** | Weighted 0–100 attention score blending eye confidence, pitch, and yaw for a single at-a-glance metric |
| **Face-lost detection** | Detects when the driver's head drops below the camera — escalates to a **FACE LOST** alert instead of going silent during microsleep |
| **Multi-channel alerts** | Four independent accumulator-based alert timers with priority ordering |
| **Audible alarm** | Looping MP3 alarm via Windows MCI when any alert fires |
| **Telegram integration** | Sends a cropped snapshot of the drowsy/distracted frame to a Telegram chat with configurable cooldown |
| **Live HUD overlay** | Attention gauge, confidence bars, head-pose angle bars, pose minimap, and status indicator rendered on the video feed |
| **3D head axes** | Real-time RGB orientation axes projected onto the detected face |
| **Performance throttling** | MediaPipe runs every Nth frame (configurable) to maintain high FPS |

### Alert Channels

| Alert | Trigger | Time to Fire | Overlay |
|---|---|---|---|
| **Head Nodding** | Pitch < −20° (head down) | 2.0 s | `HEAD NODDING - DROWSY!` |
| **Distracted** | \|Yaw\| > 30° (looking away) | 1.5 s | `DISTRACTED - WATCH ROAD!` |
| **Combined** | YOLO drowsy (>0.3) **+** head down | 1.5 s | `HEAD NODDING - DROWSY!` |
| **YOLO-only** | YOLO drowsy (>0.5) | 4.0 s | `DROWSINESS DETECTED!` |
| **Face Lost** | Face disappeared during drowsy/head-down state | 1.5 s | `FACE LOST — POSSIBLE MICROSLEEP!` |
| **Face Lost (clean)** | Face disappeared during alert state | 3.0 s | `FACE LOST — POSSIBLE MICROSLEEP!` |

Priority: **combined / head-nodding > face-lost > distracted > YOLO-only**

---

## 📁 Project Structure

```
.
├── main.py                  # Main application loop
├── best.pt                  # YOLO eye-state detection model (~6 MB)
├── face_landmarker.task     # MediaPipe face landmark model (~3.6 MB)
├── alert.mp3               # Audible alarm sound
├── requirements.txt         # Python dependencies
├── .env.example             # Template for Telegram credentials
├── LICENSE                  # MIT License
├── README.md                # This file
└── yolo/
    ├── __init__.py          # Package init
    ├── config.py            # All tunable constants & thresholds
    ├── detector.py          # YOLO + MediaPipe model initialisation
    ├── attention.py         # Attention scoring & timer state machine
    ├── head_pose.py         # solvePnP head-pose estimation
    ├── drawing.py           # HUD, confidence bars, pose minimap, alerts, axes
    ├── telegram.py          # Telegram photo dispatch with cooldown
    └── alarm.py             # Windows MCI looping MP3 alarm
```

---

## 🛠️ Requirements

- **Python** 3.10+
- **Windows** (alarm uses Windows MCI; see [Adapting for Linux/macOS](#-adapting-for-linux--macos))
- **Webcam** (built-in or USB)

---

## 📦 Installation

```bash
# 1. Clone the repository
git clone https://github.com/your-username/driver-drowsiness-detection.git
cd driver-drowsiness-detection

# 2. (Optional) Create and activate a virtual environment
python -m venv venv
venv\Scripts\activate       # Windows
# source venv/bin/activate  # Linux/macOS

# 3. Install dependencies
pip install -r requirements.txt

# 4. (Optional) Set up Telegram alerts
copy .env.example .env
# Edit .env with your bot token and chat ID
```

---

## 🚀 Usage

```bash
python main.py
```

- A window titled **"Drowsiness Detection"** opens showing your webcam feed
- The left sidebar displays the attention gauge, eye-confidence bars, head-pose angles, a pose minimap, and a status indicator
- When an alert fires, the screen flashes with a red overlay and the alarm plays
- Press **Q** to quit

### Telegram Setup (optional)

1. Copy `.env.example` to `.env`:
   ```bash
   copy .env.example .env
   ```
2. Create a bot with [@BotFather](https://t.me/BotFather) on Telegram
3. Get your chat ID from [@userinfobot](https://t.me/userinfobot)
4. Edit `.env` with your credentials:
   ```
   TELEGRAM_BOT_TOKEN=123456:ABC-DEF1234gh
   TELEGRAM_CHAT_ID=123456789
   ```

Snapshots are sent at most once every 30 seconds (configurable via `TelegramCooldown` in `yolo/config.py`).

---

## ⚙️ Configuration

All tunable constants live in **[`yolo/config.py`](yolo/config.py)**:

| Section | Key Constants | Default |
|---|---|---|
| **Head Pose** | `HeadDownPitch`, `HeadYawThreshold`, `HeadRollThreshold` | 20°, 30°, 10° |
| **Alert Timers** | `HeadDownTime`, `HeadAwayTime`, `CombinedDrowsyTime` | 2.0s, 1.5s, 1.5s |
| **Face Lost** | `FaceLostDrowsyTime`, `FaceLostCleanTime` | 1.5s, 3.0s |
| **YOLO** | `YoloDrowsyThreshold`, `YoloDrowsyWeak`, `YoloDrowsyDuration` | 0.5, 0.3, 4.0s |
| **Attention** | `AttentionFocusedMin`, `AttentionUnfocusedMin` | 80, 50 |
| **Performance** | `HeadPoseEveryN`, `TelegramCooldown` | 2, 30s |
| **Layout** | `FrameWidth`, `FrameHeight`, `HudPanel` | 1280, 720, 275px |

---

## 🧠 How It Works

### Eye-State Detection (YOLO)
A custom-trained YOLO model (`best.pt`) detects eye regions and classifies them as:
- **Class 0 — Drowsy** (eyes closed or heavy-lidded)
- **Class 1 — Alert** (eyes open)

The model runs on every frame via Ultralytics YOLO inference.

### Head-Pose Estimation (MediaPipe)
1. MediaPipe Face Landmarker extracts **468 facial landmarks** per frame
2. Six key landmarks (nose tip, chin, left/right eye corners, left/right mouth corners) are fed into OpenCV's **`solvePnP`** against a generic 3D face model
3. The resulting rotation matrix is decomposed into **pitch**, **yaw**, and **roll** Euler angles

```
Pitch > 0  = looking up      Pitch < 0  = looking down (⚠ drowsiness)
Yaw   > 0  = looking right   Yaw   < 0  = looking left  (⚠ distracted)
Roll  > 0  = tilt right      Roll  < 0  = tilt left
```

### Attention Scoring
A weighted 0–100 score blends three signals:
- **Eye penalty** (weight 50): YOLO drowsy confidence
- **Pitch penalty** (weight 40): head-down angle normalized to 30°
- **Yaw penalty** (weight 30): absolute yaw normalized to 45°

Zones: **Focused** (≥80), **Unfocused** (50–79), **Low** (<50).

### Face-Lost Detection
When the driver nods off completely, the face disappears from the camera. Instead of going silent, the system:
1. Snapshots the last known state (drowsy? head down?)
2. If the prior state was risky → fires after **1.5 seconds**
3. If the prior state was clean → fires after **3.0 seconds**

### Combined Logic
Four independent accumulator-based timers run in parallel. The combined channel lowers the YOLO confidence threshold from 0.5 → 0.3 when head-down is also detected, providing **faster alerts when both signals agree**.

---

## 🔧 Adapting for Linux / macOS

The alarm system uses **Windows MCI** (`ctypes.windll.winmm`). To run on other platforms, replace `yolo/alarm.py` with:

```python
# Example using playsound (pip install playsound)
import threading
from playsound import playsound

_IsPlayingAlarm = False

def UpdateAlarm(Active):
    global _IsPlayingAlarm
    if Active and not _IsPlayingAlarm:
        _IsPlayingAlarm = True
        threading.Thread(target=playsound, args=("alert.mp3",), daemon=True).start()
    elif not Active:
        _IsPlayingAlarm = False
```

---

## 📄 License

MIT — see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgements

- [Ultralytics YOLO](https://github.com/ultralytics/ultralytics)
- [MediaPipe](https://github.com/google-ai-edge/mediapipe)
- [OpenCV](https://opencv.org/)
