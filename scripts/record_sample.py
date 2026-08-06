"""Record a short webcam session for integration/replay testing."""
import argparse
import cv2

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="testdata/sample.mp4")
    ap.add_argument("--seconds", type=int, default=30)
    args = ap.parse_args()

    cap = cv2.VideoCapture(0)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    writer = cv2.VideoWriter(args.out, cv2.VideoWriter_fourcc(*"mp4v"), 30,
                             (640, 480))
    print("Recording — move your head naturally. Ctrl+C to stop early.")
    frames = 0
    while frames < args.seconds * 30:
        ok, frame = cap.read()
        if not ok:
            break
        writer.write(frame)
        frames += 1
    writer.release()
    cap.release()
    print(f"Wrote {args.out} ({frames} frames)")

if __name__ == "__main__":
    main()
