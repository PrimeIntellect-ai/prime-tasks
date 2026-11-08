#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv libgl1 libglib2.0-0
    pip3 install pytest numpy opencv-python-headless scapy

    mkdir -p /app
    mkdir -p /home/user/analysis_env

    python3 -c "
import numpy as np
import cv2
from scapy.all import IP, UDP, Ether
from scapy.utils import PcapWriter
import struct
import os

video_path = '/app/surveillance.mp4'
width, height = 320, 240
out = cv2.VideoWriter(video_path, cv2.VideoWriter_fourcc(*'mp4v'), 30, (width, height), isColor=False)
frames = []
rs = np.random.RandomState(123)
for i in range(100):
    frame = rs.randint(0, 256, (height, width), dtype=np.uint8)
    frames.append(frame)
    out.write(frame)
out.release()

rs_noise = np.random.RandomState(42)
noise_matrix = rs_noise.rand(64, 64).astype(np.float32)
np.save('/app/ground_truth_noise.npy', noise_matrix)

dump_path = '/app/memory.dmp'
with open(dump_path, 'wb') as f:
    f.write(os.urandom(1024))
    f.write(b'NOISE_SEED_V1_8899')
    f.write(noise_matrix.tobytes())
    f.write(os.urandom(2048))

pkts = PcapWriter('/app/traffic.pcap', append=True, sync=True)
frame_indices = [5, 15, 25, 35, 45, 55, 65, 75, 85, 95]
for idx in frame_indices:
    original = frames[idx]
    cy, cx = height // 2, width // 2
    crop = original[cy-32:cy+32, cx-32:cx+32].astype(np.float32) / 255.0
    corrupted = (crop * 0.5) + (noise_matrix * 0.5)

    payload = struct.pack('<I', idx) + corrupted.tobytes()
    pkt = Ether()/IP(dst='127.0.0.1')/UDP(dport=1337)/payload
    pkts.write(pkt)
pkts.close()

with open('/home/user/analysis_env/requirements.txt', 'w') as f:
    f.write('numpy==1.20.0\\nscapy==2.4.4\\nopencv-python==4.5.1.48\\n# Agent must update versions to be compatible with python 3.x\\n')
"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
