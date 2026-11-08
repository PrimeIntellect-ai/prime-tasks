#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libgl1-mesa-glx libglib2.0-0 ffmpeg
    pip3 install pytest opencv-python numpy Flask FastAPI uvicorn requests xmltodict

    useradd -m -s /bin/bash user || true
    mkdir -p /app
    mkdir -p /home/user/artifacts

    cat << 'EOF' > /tmp/setup.py
import cv2
import numpy as np
import struct
import os

# Generate video
out = cv2.VideoWriter('/app/deploy_sequence.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (100, 100))
bits = [1, 0, 1, 0, 1, 0, 1, 1, 1, 1, 0, 0, 1, 1, 0, 1]
for b in bits:
    color = 255 if b else 0
    frame = np.full((100, 100, 3), color, dtype=np.uint8)
    out.write(frame)
for _ in range(14):
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    out.write(frame)
out.release()

# Generate artifacts
def make_bin(id_, deps, xml_str):
    magic = b'ARTF'
    id_bytes = struct.pack('<I', id_)
    n_deps = len(deps)
    n_deps_bytes = struct.pack('<I', n_deps)
    deps_bytes = b''.join(struct.pack('<I', d) for d in deps)
    xml_bytes = xml_str.encode('utf-8')
    m_bytes = struct.pack('<I', len(xml_bytes))
    return magic + id_bytes + n_deps_bytes + deps_bytes + m_bytes + xml_bytes

files = [
    (43981, [1001, 1002], '<artifact><name>root-app</name><version>1.0</version></artifact>'),
    (1001, [1003], '<artifact><name>lib-a</name><version>2.0</version></artifact>'),
    (1002, [1003, 43981], '<artifact><name>lib-b</name><version>1.5</version></artifact>'),
    (1003, [1001], '<artifact><name>lib-core</name><version>0.9</version></artifact>')
]

for id_, deps, xml_str in files:
    with open(f'/home/user/artifacts/{id_}.bin', 'wb') as f:
        f.write(make_bin(id_, deps, xml_str))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
