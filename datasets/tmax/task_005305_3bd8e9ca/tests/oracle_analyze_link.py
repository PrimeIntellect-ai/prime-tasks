import sys
import cv2
import numpy as np

def main():
    frame_idx = int(sys.argv[1])
    threshold = int(sys.argv[2])

    cap = cv2.VideoCapture('/app/switch_lights.mp4')
    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
    ret, frame = cap.read()
    if not ret:
        print("LINK_DOWN")
        sys.exit(0)

    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    roi = gray[0:50, 0:50]
    avg_brightness = np.mean(roi)

    if avg_brightness > threshold:
        print("LINK_UP")
    else:
        print("LINK_DOWN")

if __name__ == "__main__":
    main()
