#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr
pip3 install pytest Pillow pytesseract

cat << 'EOF' > /tmp/setup.py
import os
import json
import random
import subprocess
from PIL import Image, ImageDraw, ImageFont

os.makedirs("/app", exist_ok=True)

# Generate Video Frames
frames_dir = "/app/frames"
os.makedirs(frames_dir, exist_ok=True)

base_ts = 1700000000
configs = []
logs = []

# Mock large file generation and video frames
for i in range(50):
    ts = base_ts + (i * 10)
    hash_val = f"{random.randint(0, 0xFFFFFFFF):08x}"

    # Payload generation with drift
    base_tokens = ["nginx_conf", "port_80", "ssl_cert", "user_admin", "worker_nodes_4", "timeout_30s"]
    random.shuffle(base_tokens)
    if i > 0 and i % 3 == 0:
        base_tokens.pop()
        base_tokens.append(f"new_feature_{i}")

    payload = " ".join(base_tokens)

    configs.append((ts, hash_val, payload))

    # Generate log entry
    logs.append(json.dumps({"timestamp": ts, "event_type": "config_commit", "config_payload": payload}))

    # Generate image for video
    img = Image.new('RGB', (640, 480), color = (0, 0, 0))
    if i not in [15, 16, 32]: # Simulate corrupted/black frames
        d = ImageDraw.Draw(img)
        # Assuming default font exists, else simple text rendering
        d.text((50, 200), f"TS: {ts} | HASH: {hash_val}", fill=(255,255,255))
    img.save(f"{frames_dir}/frame_{i:04d}.png")

# Fill agent_logs.jsonl with noise + signal
with open("/app/agent_logs.jsonl", "w") as f:
    for ts in range(base_ts - 100, base_ts + 600):
        if ts in [c[0] for c in configs]:
            idx = [c[0] for c in configs].index(ts)
            f.write(logs[idx] + "\n")
        else:
            f.write(json.dumps({"timestamp": ts, "event_type": "system_ping", "status": "ok"}) + "\n")
        # Add volume
        for _ in range(100):
            f.write(json.dumps({"timestamp": ts, "event_type": "debug", "msg": "junk data"}) + "\n")

# Compile video
subprocess.run([
    "ffmpeg", "-y", "-framerate", "1", "-i", f"{frames_dir}/frame_%04d.png", 
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "/app/config_dashboard.mp4"
], check=True)

# Cleanup frames
import shutil
shutil.rmtree(frames_dir)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
