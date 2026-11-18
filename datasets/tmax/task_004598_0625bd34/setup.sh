#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libzbar0 libgl1-mesa-glx libglib2.0-0
    pip3 install pytest opencv-python pyzbar rdflib qrcode pillow numpy

    mkdir -p /app

    cat << 'EOF' > /app/org_graph.ttl
@prefix org: <http://example.org/org#> .

org:EMP015 org:hasRole org:Admin .

org:EMP001 org:reportsTo org:EMP002 .
org:EMP002 org:reportsTo org:EMP003 .
org:EMP003 org:hasRole org:Admin .

org:EMP007 org:reportsTo org:EMP008 .
org:EMP008 org:reportsTo org:EMP009 .
org:EMP009 org:hasRole org:User .

org:EMP042 org:reportsTo org:EMP043 .
org:EMP043 org:hasRole org:Manager .
EOF

    python3 -c '
import cv2
import qrcode
import numpy as np
from PIL import Image

fps = 30
width, height = 640, 480
out = cv2.VideoWriter("/app/entry_log.mp4", cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height))

emps = ["EMP001", "EMP007", "EMP015", "EMP042"]

for emp in emps:
    qr = qrcode.QRCode(version=1, box_size=10, border=4)
    qr.add_data(emp)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white").convert("RGB")
    img_np = np.array(img)

    qr_h, qr_w, _ = img_np.shape

    frame = np.ones((height, width, 3), dtype=np.uint8) * 255

    start_y = (height - qr_h) // 2
    start_x = (width - qr_w) // 2
    frame[start_y:start_y+qr_h, start_x:start_x+qr_w] = img_np

    for _ in range(fps):
        out.write(frame)

out.release()
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
