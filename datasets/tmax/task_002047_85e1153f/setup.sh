#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app
    mkdir -p /home/user/tracker
    mkdir -p /hidden

    cat << 'EOF' > /tmp/setup.py
import cv2
import numpy as np
import json
import os

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/drone_tracking.mp4', fourcc, 30.0, (640, 480))

gt = []
x, y = 100, 100
w, h = 50, 50

for i in range(60):
    frame = np.ones((480, 640, 3), dtype=np.uint8) * 255
    if i in [15, 30, 45]:
        frame = np.random.randint(0, 256, (480, 640, 3), dtype=np.uint8)
    else:
        cv2.rectangle(frame, (x, y), (x+w, y+h), (0, 0, 0), -1)

    out.write(frame)
    gt.append([x, y, w, h])

    x += 5
    y += 3

out.release()

with open('/hidden/ground_truth.json', 'w') as f:
    json.dump(gt, f)
EOF

    python3 /tmp/setup.py

    cat << 'EOF' > /home/user/tracker/track.py
import cv2
import numpy as np
import json

def recursive_mean_shift(frame, bbox, iteration=0):
    x, y, w, h = bbox
    y_clip = max(0, min(y, frame.shape[0]-h))
    x_clip = max(0, min(x, frame.shape[1]-w))
    roi = frame[y_clip:y_clip+h, x_clip:x_clip+w]

    # If the frame is highly corrupted (noise), variance is very high
    if np.var(roi) > 5000:
        # Bug: infinite recursion
        return recursive_mean_shift(frame, bbox, iteration)

    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    _, thresh = cv2.threshold(gray, 50, 255, cv2.THRESH_BINARY_INV)
    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    if contours:
        c = max(contours, key=cv2.contourArea)
        x_new, y_new, w_new, h_new = cv2.boundingRect(c)
        return [x_new, y_new, w_new, h_new]

    return bbox

def track_video(video_path):
    cap = cv2.VideoCapture(video_path)
    bboxes = []
    bbox = [100, 100, 50, 50]
    while True:
        ret, frame = cap.read()
        if not ret:
            break

        bbox = recursive_mean_shift(frame, bbox)
        bboxes.append(bbox)

    cap.release()
    with open('/home/user/tracker/output.json', 'w') as f:
        json.dump(bboxes, f)

if __name__ == '__main__':
    track_video('/app/drone_tracking.mp4')
EOF

    cat << 'EOF' > /hidden/evaluate.py
import json
import sys

def calculate_iou(boxA, boxB):
    xA = max(boxA[0], boxB[0])
    yA = max(boxA[1], boxB[1])
    xB = min(boxA[0] + boxA[2], boxB[0] + boxB[2])
    yB = min(boxA[1] + boxA[3], boxB[1] + boxB[3])

    interArea = max(0, xB - xA) * max(0, yB - yA)
    boxAArea = boxA[2] * boxA[3]
    boxBArea = boxB[2] * boxB[3]
    iou = interArea / float(boxAArea + boxBArea - interArea)
    return iou

def main():
    with open('/hidden/ground_truth.json', 'r') as f:
        gt = json.load(f)
    try:
        with open('/home/user/tracker/output.json', 'r') as f:
            pred = json.load(f)
    except Exception as e:
        print(f"Error reading prediction: {e}")
        sys.exit(1)

    if len(gt) != len(pred):
        print(f"Frame count mismatch. Expected {len(gt)}, got {len(pred)}")
        sys.exit(1)

    ious = [calculate_iou(g, p) for g, p in zip(gt, pred)]
    avg_iou = sum(ious) / len(ious)
    print(f"Average IoU: {avg_iou:.4f}")

    if avg_iou >= 0.85:
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
