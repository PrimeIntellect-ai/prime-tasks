import sys
import cv2

def main():
    video_path = "/app/profiling.mp4"
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        sys.exit(1)

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            frame_idx = int(line)
        except ValueError:
            print(-1)
            continue

        if frame_idx < 0 or frame_idx >= total_frames:
            print(-1)
            continue

        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
        ret, frame = cap.read()
        if ret:
            row_sum = int(frame[0, :, :].sum())
            print(row_sum)
        else:
            print(-1)

if __name__ == "__main__":
    main()
