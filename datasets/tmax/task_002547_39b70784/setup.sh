#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-opencv python3-numpy
pip3 install pytest

mkdir -p /app/corpus/clean /app/corpus/evil

cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/factory_lights.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (300, 100))

states = [
    (1, 0, 0),
    (1, 1, 0),
    (0, 1, 1),
    (0, 0, 1),
    (1, 1, 1)
]

for r, g, b in states:
    for _ in range(10):
        frame = np.zeros((100, 300, 3), dtype=np.uint8)
        if r: frame[:, 0:100, 2] = 200
        if g: frame[:, 100:200, 1] = 200
        if b: frame[:, 200:300, 0] = 200
        out.write(frame)

out.release()
EOF

python3 /tmp/gen_video.py

cat << 'EOF' > /app/corpus/clean/clean_1.json
{"timestamp": "2024-01-01T12:05:00Z", "temp": 25.5, "pressure": 15.0}
EOF
cat << 'EOF' > /app/corpus/clean/clean_2.json
{"timestamp": "2024-01-01T12:05:01Z", "temp": 0.0, "pressure": 20.0}
EOF

cat << 'EOF' > /app/corpus/evil/evil_1.json
{"timestamp": "2024-01-01 12:05:00", "temp": 25.5, "pressure": 15.0}
EOF
cat << 'EOF' > /app/corpus/evil/evil_2.json
{"timestamp": "2024-01-01T12:05:00Z", "temp": 150.1, "pressure": 15.0}
EOF
cat << 'EOF' > /app/corpus/evil/evil_3.json
{"timestamp": "2024-01-01T12:05:00Z", "temp": 25.5, "pressure": 9.9}
EOF
cat << 'EOF' > /app/corpus/evil/evil_4.json
{"timestamp": "2024-01-01T12:05:00Z", "temp": "25.5", "pressure": 15.0}
EOF
cat << 'EOF' > /app/corpus/evil/evil_5.json
{"timestamp": "2024-01-01T12:05:00Z", "temp": 25.5, "pressure": 15.0, "extra": 1}
EOF
cat << 'EOF' > /app/corpus/evil/evil_6.json
{malformed
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
