#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends python3 python3-pip ffmpeg
    pip3 install --no-cache-dir pytest pillow

    mkdir -p /app

    # Create Oracle
    cat << 'EOF' > /app/oracle.py
import sys
if len(sys.argv) < 2:
    sys.exit(1)
text = sys.argv[1].encode('utf-8')
iv = [0x5A, 0x3C, 0x99, 0x42]
out = bytearray(len(text))
for i in range(len(text)):
    if i % 2 == 0:
        out[i] = text[i] ^ iv[i % 4]
    else:
        out[i] = text[i] ^ ((iv[i % 4] + 1) & 0xFF)
print(out.hex().upper())
EOF
    chmod +x /app/oracle.py

    cat << 'EOF' > /app/payload_encoder
#!/bin/bash
python3 /app/oracle.py "$1"
EOF
    chmod +x /app/payload_encoder

    # Create Video
    cat << 'EOF' > /app/make_video.py
from PIL import Image, ImageDraw
import os
import subprocess

os.makedirs('/app/frames', exist_ok=True)
for i in range(60):
    img = Image.new('RGB', (800, 600), color='black')
    d = ImageDraw.Draw(img)
    if 10 <= i <= 20:
        text = "gcc -o payload_encoder main.c -lcrypto\nLinker error: undefined reference to 'XOR_IV'\nNote: IV must be 0x5A, 0x3C, 0x99, 0x42."
    elif 30 <= i <= 40:
        text = "Thread 1 (evens) & Thread 2 (odds) race condition fixed.\nEvens processed before odds.\nEvens: XOR with IV[i%4]\nOdds: XOR with (IV[i%4] + 1)"
    else:
        text = "user@box:~$ "
    d.text((10,10), text, fill=(255,255,255))
    img.save(f'/app/frames/frame_{i:03d}.png')

subprocess.run(['ffmpeg', '-y', '-framerate', '30', '-i', '/app/frames/frame_%03d.png', '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '/app/evidence.mp4'], check=True)
EOF
    python3 /app/make_video.py
    rm -rf /app/frames /app/make_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
