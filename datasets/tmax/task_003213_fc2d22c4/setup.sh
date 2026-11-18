#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest flask fastapi uvicorn requests opencv-python-headless

    mkdir -p /app
    cat << 'EOF' > /app/generate.py
import os
import subprocess

os.makedirs('/app/frames', exist_ok=True)
for i in range(100):
    color = 255 if i in [25, 42, 88] else 0
    with open(f'/app/frames/frame_{i:03d}.pgm', 'w') as f:
        f.write(f"P2\n10 10\n255\n" + (" ".join([str(color)]*10) + "\n")*10)

subprocess.run([
    "ffmpeg", "-y", "-framerate", "30", "-i", "/app/frames/frame_%03d.pgm",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "/app/dashboard_recording.mp4"
], check=True)

with open('/app/telemetry_stream.jsonl', 'w') as f:
    f.write('{"frame_index": 25, "sensor_reading": "alert_1"}\\u00\n')
    f.write('{"frame_index": 42, "sensor_reading": "alert_2"}\n')
    f.write('{"frame_index": 88, "sensor_reading": "alert_3"}\\uZZZZ\n')
EOF
    python3 /app/generate.py
    rm -rf /app/frames /app/generate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
