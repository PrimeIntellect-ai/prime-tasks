#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr
pip3 install pytest opencv-python-headless numpy

mkdir -p /app

cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

texts = [
    "TXN: U101 -> U102 : 500",
    "TXN: U102 -> U103 : 300",
    "TXN: U103 -> U101 : 200",
    "TXN: U200 -> U201 : 100",
    "TXN: U999 -> U888 : 50"
]

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/compliance_log.mp4', fourcc, 1.0, (800, 200))

for text in texts:
    img = np.zeros((200, 800, 3), dtype=np.uint8)
    # Put text in the image
    cv2.putText(img, text, (50, 100), cv2.FONT_HERSHEY_SIMPLEX, 1.5, (255, 255, 255), 3, cv2.LINE_AA)
    # Write 5 frames for each text
    for _ in range(5):
        out.write(img)

out.release()
EOF

python3 /tmp/gen_video.py
rm /tmp/gen_video.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
