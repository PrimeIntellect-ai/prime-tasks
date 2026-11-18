#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc make
pip3 install pytest flask fastapi uvicorn requests

mkdir -p /app
mkdir -p /home/user

# Create oracle decoder
cat << 'EOF' > /app/oracle_decoder.c
#include <stdio.h>
int main(int argc, char** argv) {
    return 0;
}
EOF
gcc -o /app/oracle_decoder /app/oracle_decoder.c
chmod +x /app/oracle_decoder

# Create python script to generate video
cat << 'EOF' > /app/gen_video.py
import os
import subprocess

width, height = 20, 20
frames = 1024

payload = bytearray(1024)
for i in range(128):
    chunk_id = i
    total_chunks = 32
    payload[i*8] = (chunk_id >> 8) & 0xFF
    payload[i*8+1] = chunk_id & 0xFF
    payload[i*8+2] = (total_chunks >> 8) & 0xFF
    payload[i*8+3] = total_chunks & 0xFF
    payload[i*8+4] = 0x41
    payload[i*8+5] = 0x42
    payload[i*8+6] = 0x43
    payload[i*8+7] = 0x44

raw_data = bytearray(frames * width * height * 3)
for f in range(frames):
    val = payload[f]
    idx = f * width * height * 3 + (10 * width + 10) * 3
    raw_data[idx] = val
    raw_data[idx+1] = val
    raw_data[idx+2] = val

with open('/app/raw.rgb', 'wb') as f:
    f.write(raw_data)

subprocess.run([
    'ffmpeg', '-y', '-f', 'rawvideo', '-pixel_format', 'rgb24', 
    '-video_size', f'{width}x{height}', '-framerate', '30', 
    '-i', '/app/raw.rgb', '-c:v', 'libx264', '-preset', 'ultrafast', 
    '-qp', '0', '/app/web_traffic_capture.mp4'
], check=True)
EOF

python3 /app/gen_video.py
rm /app/gen_video.py /app/raw.rgb /app/oracle_decoder.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
