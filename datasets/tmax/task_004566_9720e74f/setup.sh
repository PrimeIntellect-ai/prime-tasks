#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick ghostscript fonts-liberation
    pip3 install pytest

    mkdir -p /app

    # Create the oracle binary
    cat << 'EOF' > /app/oracle_analyzer.py
#!/usr/bin/env python3
import sys, hashlib, base64

if len(sys.argv) != 2:
    sys.exit(1)

try:
    raw_bytes = bytes.fromhex(sys.argv[1])
except ValueError:
    print("ERR_DECODE")
    sys.exit(0)

try:
    http_text = raw_bytes.decode('utf-8')
except UnicodeDecodeError:
    print("ERR_DECODE")
    sys.exit(0)

lines = http_text.split('\r\n')
session = None
cert = None

for line in lines:
    if line.lower().startswith('cookie:'):
        parts = line[7:].split(';')
        for p in parts:
            p = p.strip()
            if p.startswith('session='):
                session = p[8:]
    elif line.lower().startswith('x-cert-chain:'):
        cert = line[13:].strip()

if not session or not cert:
    print("ERR_MISSING")
    sys.exit(0)

if "CN=Admin" not in cert or not hashlib.md5(cert.encode()).hexdigest().endswith('f'):
    print("ERR_CERT")
    sys.exit(0)

try:
    enc_bytes = base64.b64decode(session)
except Exception:
    print("ERR_B64")
    sys.exit(0)

dec_bytes = bytes([b ^ 85 for b in enc_bytes])
try:
    dec_text = dec_bytes.decode('utf-8')
except Exception:
    print("ERR_AUTH")
    sys.exit(0)

if dec_text.startswith("SECURE_DEV_"):
    print(f"SUCCESS:{dec_text}")
else:
    print("ERR_AUTH")
EOF
    chmod +x /app/oracle_analyzer.py

    # Generate the video fixture
    mkdir -p /tmp/frames
    for i in $(seq 1 150); do
        if [ $i -eq 60 ]; then
            convert -size 640x480 xc:black -fill white -pointsize 24 -draw "text 50,100 'export XOR_KEY=85\nexport AUTH_PREFIX=\"SECURE_DEV_\"'" /tmp/frames/frame_$(printf "%03d" $i).png
        else
            convert -size 640x480 xc:black -fill white -pointsize 24 -draw "text 50,100 'Tail log...'" /tmp/frames/frame_$(printf "%03d" $i).png
        fi
    done
    ffmpeg -y -framerate 30 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/intercept_debug.mp4
    rm -rf /tmp/frames

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
