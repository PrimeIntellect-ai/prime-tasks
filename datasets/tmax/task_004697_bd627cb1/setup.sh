#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++ python3-opencv python3-numpy
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /app

    cat << 'EOF' > /tmp/setup_env.py
import cv2
import numpy as np
import csv
import json

# Generate Video
fps = 10
duration = 5 # seconds
frames = fps * duration

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/ui_test.mp4', fourcc, fps, (320, 240))

screen_loads = 0
for i in range(frames):
    frame = np.zeros((240, 320, 3), dtype=np.uint8)
    # Background color
    frame[:] = (50, 50, 50)

    # Screen load triggers at frame 5, 15, 25, 40
    if i in [5, 15, 25, 40]:
        frame[0:10, 0:10] = (255, 255, 255)
        screen_loads += 1
    else:
        frame[0:10, 0:10] = (0, 0, 0)

    out.write(frame)
out.release()

# Generate CSV
csv_data = [
    ["timestamp_ms", "screen_id", "loc_key", "english_source", "lang_target", "translation"],
    [500, "screen_A", "greeting", "Hello", "es", "Hola"],
    [510, "screen_A", "greeting", "Hello", "es", "Hola"], # Duplicate
    [520, "screen_A", "farewell", "Goodbye", "fr", "Au revoir"],
    [530, "screen_A", "missing_key", "Test", "de", "MISSING"], # Invalid
    [1500, "screen_B", "title", "Main Menu", "es", "Menú principal"],
    [1510, "screen_B", "start", "Start", "es", "Empezar"],
    [1520, "screen_B", "title", "Main Menu", "fr", "Menu principal"],
]

with open('/home/user/raw_loc_requests.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(csv_data)

# Ground truth expected output
expected = {
    "total_screen_loads_from_video": 4,
    "screens": {
        "screen_A": {
            "unique_keys": 2,
            "languages_covered": ["es", "fr"]
        },
        "screen_B": {
            "unique_keys": 2,
            "languages_covered": ["es", "fr"]
        }
    }
}
with open('/tmp/expected_summary.json', 'w') as f:
    json.dump(expected, f)

EOF

    python3 /tmp/setup_env.py

    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod 777 /tmp/expected_summary.json
