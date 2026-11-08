#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-opencv
    pip3 install pytest numpy

    mkdir -p /app/service /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/service/flash_detector.py
import cv2
import sys

def detect_flashes(video_path):
    cap = cv2.VideoCapture(video_path)
    flash_count = 0
    is_flashing = False

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        # BUG: OpenCV uses BGR, but we treat it as RGB here, and formula is wrong
        # Correct luminance formula: Y = 0.299*R + 0.587*G + 0.114*B
        # Buggy formula: Y = 0.5*B + 0.5*G + 0.5*R
        b, g, r = cv2.split(frame)
        luminance = 0.5 * b + 0.5 * g + 0.5 * r
        avg_lum = luminance.mean()

        if avg_lum > 200:
            if not is_flashing:
                flash_count += 1
                is_flashing = True
        else:
            is_flashing = False

    cap.release()

    with open('/home/user/flash_count.txt', 'w') as f:
        f.write(str(flash_count))

if __name__ == "__main__":
    detect_flashes(sys.argv[1])
EOF

    cat << 'EOF' > /app/service/requirements.txt
opencv-python==4.5.3.56
numpy==1.19.0
# Conflict: numpy 1.19.0 is incompatible with newer python versions or opencv requires higher numpy
EOF

    echo '{"timestamp": "2023-10-01T03:00:00Z", "sensor_data": {"temp": 22}}' > /app/corpus/clean/log1.json
    echo '{"timestamp": "2023-10-01T03:01:00Z", "sensor_data": {"temp": 23}}' > /app/corpus/clean/log2.json

    echo -e '{"timestamp": "2023-10-01T03:02:00Z", "sensor_data": {"temp": \xff\xfe}}' > /app/corpus/evil/log1.json
    echo '{"sensor_data": {"temp": 22}}' > /app/corpus/evil/log2.json
    echo '{"timestamp": "2023-10-01", "sensor_data": {' > /app/corpus/evil/log3.json

    python3 -c "
import cv2
import numpy as np

out = cv2.VideoWriter('/app/cctv_feed.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (320, 240))
for i in range(300):
    if i in [30, 31, 32, 90, 91, 92, 150, 151, 152, 210, 211, 212, 270, 271, 272]:
        frame = np.ones((240, 320, 3), dtype=np.uint8) * 255
    else:
        frame = np.zeros((240, 320, 3), dtype=np.uint8)
    out.write(frame)
out.release()
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
