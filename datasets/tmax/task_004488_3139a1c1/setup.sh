#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        libsm6 \
        libxext6 \
        libzbar0

    pip3 install pytest pyzbar Pillow qrcode[pil] opencv-python-headless

    mkdir -p /app/corpus/clean /app/corpus/evil /home/user/pipeline

    # Create legacy_hash.js
    cat << 'EOF' > /app/legacy_hash.js
function calculateHash(data) {
    let hash = 0x811c9dc5;
    for (let i = 0; i < data.length; i++) {
        hash ^= data.charCodeAt(i);
        hash = (hash * 0x01000193) >>> 0;
    }
    return hash.toString(16).padStart(8, '0');
}
module.exports = { calculateHash };
EOF

    # Generate video and corpus
    python3 -c '
import cv2
import numpy as np
import qrcode
import json
import os

# Generate QR code
qr = qrcode.QRCode(version=1, box_size=10, border=4)
qr.add_data("ROOT:com.mobile.core.app")
qr.make(fit=True)
img = qr.make_image(fill_color="black", back_color="white").convert("RGB")
qr_img = np.array(img)
qr_img = qr_img[:, :, ::-1].copy()

width, height = 640, 480
fps = 30
fourcc = cv2.VideoWriter_fourcc(*"mp4v")
out = cv2.VideoWriter("/app/ui_test_recording.mp4", fourcc, fps, (width, height))

for i in range(90):
    frame = np.ones((height, width, 3), dtype=np.uint8) * 255
    if 30 <= i <= 60:
        h, w, _ = qr_img.shape
        y_offset = (height - h) // 2
        x_offset = (width - w) // 2
        frame[y_offset:y_offset+h, x_offset:x_offset+w] = qr_img
    out.write(frame)
out.release()

def fnv1a(data):
    hash_val = 0x811c9dc5
    for char in data:
        hash_val ^= ord(char)
        hash_val = (hash_val * 0x01000193) & 0xffffffff
    return f"{hash_val:08x}"

clean1 = {
    "com.mobile.core.app": {
        "deps": ["libA", "libB"],
        "expected_hash": fnv1a("com.mobile.core.app,libA,libB")
    },
    "libA": {"deps": [], "expected_hash": ""},
    "libB": {"deps": [], "expected_hash": ""}
}

clean2 = {
    "com.mobile.core.app": {
        "deps": ["libC"],
        "expected_hash": fnv1a("com.mobile.core.app,libC,libD")
    },
    "libC": {"deps": ["libD"], "expected_hash": ""},
    "libD": {"deps": [], "expected_hash": ""}
}

evil1 = {
    "com.mobile.core.app": {
        "deps": ["libA"],
        "expected_hash": fnv1a("com.mobile.core.app,libA,libB")
    },
    "libA": {"deps": ["libB"], "expected_hash": ""},
    "libB": {"deps": ["libA"], "expected_hash": ""}
}

evil2 = {
    "com.mobile.core.app": {
        "deps": ["libA"],
        "expected_hash": "deadbeef"
    },
    "libA": {"deps": [], "expected_hash": ""}
}

with open("/app/corpus/clean/update1.json", "w") as f: json.dump(clean1, f)
with open("/app/corpus/clean/update2.json", "w") as f: json.dump(clean2, f)
with open("/app/corpus/evil/cycle.json", "w") as f: json.dump(evil1, f)
with open("/app/corpus/evil/bad_hash.json", "w") as f: json.dump(evil2, f)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
