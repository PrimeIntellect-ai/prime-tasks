#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr cron
pip3 install pytest numpy opencv-python-headless pytesseract

mkdir -p /app
cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/incident_screen.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 1, (640, 480))
gt = [12, 24, 37, 45, 58]

for i in range(60):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    if i in gt:
        cv2.putText(frame, "Error 502 Bad Gateway", (50, 240), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
    else:
        cv2.putText(frame, "Normal log line", (50, 240), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
    out.write(frame)
out.release()
EOF

python3 /app/generate_video.py

useradd -m -s /bin/bash user || true

mkdir -p /home/user/manifests
mkdir -p /home/user/configs

cat << 'EOF' > /home/user/k8s_operator.py
import os
import json

MANIFEST_DIR = "/home/user/manifests"
CONFIG_DIR = "/home/user/configs"

if not os.path.exists(CONFIG_DIR):
    os.makedirs(CONFIG_DIR)

for filename in os.listdir(MANIFEST_DIR):
    if filename.endswith(".json"):
        with open(os.path.join(MANIFEST_DIR, filename), "r") as f:
            data = json.load(f)

        name = data.get("metadata", {}).get("name", "app")
        # Hardcoded socket path
        socket_path = "/var/run/upstream.sock"

        config = f"""server {{
    listen 80;
    server_name {name}.local;
    location / {{
        proxy_pass http://unix:{socket_path};
    }}
}}"""
        with open(os.path.join(CONFIG_DIR, f"{name}.conf"), "w") as f:
            f.write(config)
EOF

cat << 'EOF' > /home/user/manifests/app1.json
{
  "metadata": {
    "name": "app1",
    "annotations": {
      "nginx.ingress.kubernetes.io/socket-path": "/var/run/custom-app.sock"
    }
  }
}
EOF

chown -R user:user /home/user
chmod -R 777 /home/user
