#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc make
    pip3 install pytest pandas

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_video.py
import subprocess

text = """[1699991234] ERROR_CODE:500 - Database timeout
[1699991235] ERROR_CODE:404 - Not found
[1699991236] ERROR_CODE:500 - Database timeout
[1699991237] ERROR_CODE:200 - OK
[1699991238] ERROR_CODE:404 - Not found
[1699991239] ERROR_CODE:500 - Database timeout
Invalid line here
[1699991240] ERROR_CODE:500 - Database timeout
"""

with open('/tmp/frames.raw', 'wb') as f:
    for char in text:
        val = ord(char)
        for i in range(7, -1, -1):
            bit = (val >> i) & 1
            pixel = 255 if bit else 0
            # 16x16 frame = 256 bytes
            f.write(bytes([pixel] * 256))

subprocess.run([
    'ffmpeg', '-y', '-f', 'rawvideo', '-pixel_format', 'gray', 
    '-video_size', '16x16', '-framerate', '30', 
    '-i', '/tmp/frames.raw', '-c:v', 'libx264', 
    '-pix_fmt', 'yuv420p', '/app/etl_stream.mp4'
], check=True)
EOF

    python3 /tmp/gen_video.py

    cat << 'EOF' > /app/truth_records.csv
Timestamp,ErrorCode,Message
1699991234,500,Database timeout
1699991235,404,Not found
1699991237,200,OK
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
