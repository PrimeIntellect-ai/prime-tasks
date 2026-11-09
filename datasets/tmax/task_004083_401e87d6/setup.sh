#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++ coreutils gawk
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create the video
    cat << 'EOF' > /tmp/make_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/audit_log.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (100, 100))
for i in range(300):
    img = np.zeros((100, 100, 3), dtype=np.uint8)
    if i < 47:
        img[:] = (0, 0, 255) # BGR, so Red is (0, 0, 255)
    else:
        img[:] = (0, 255, 0) # Green
    out.write(img)
out.release()
EOF
    python3 /tmp/make_video.py

    # Helper to generate valid file
    gen_file() {
        local f=$1
        local body=$2
        local hash=$(echo -n "$body" | sha256sum | awk '{print $1}')
        echo "HASH: $hash" > "$f"
        echo -n "$body" >> "$f"
    }

    # Clean corpus
    gen_file /app/corpus/clean/valid1.txt "CSP: default-src 'self'; script-src 'self'
CERT_CHAIN: RootCA,AuthCA,LeafCA"
    gen_file /app/corpus/clean/valid2.txt "CSP: default-src 'self'
CERT_CHAIN: RootCA,LeafCA"
    gen_file /app/corpus/clean/valid3.txt "CSP: img-src *
CERT_CHAIN: RootCA,A,B,LeafCA"
    gen_file /app/corpus/clean/valid4.txt "CSP: object-src 'none'
CERT_CHAIN: RootCA,X,LeafCA"
    gen_file /app/corpus/clean/valid5.txt "CSP: base-uri 'self'
CERT_CHAIN: RootCA,Y,LeafCA"

    # Evil corpus
    gen_file /app/corpus/evil/evil1.txt "CSP: default-src 'unsafe-inline'
CERT_CHAIN: RootCA,LeafCA"
    gen_file /app/corpus/evil/evil2.txt "CSP: default-src 'self'
CERT_CHAIN: IntermediateCA,LeafCA"
    gen_file /app/corpus/evil/evil3.txt "CSP: default-src 'self'
CERT_CHAIN: RootCA,RevokedCA,LeafCA"
    gen_file /app/corpus/evil/evil5.txt "CSP: default-src 'unsafe-eval'
CERT_CHAIN: RootCA,LeafCA"

    # Evil 4: Invalid hash
    body="CSP: default-src 'self'
CERT_CHAIN: RootCA,LeafCA"
    hash=$(echo -n "wrong" | sha256sum | awk '{print $1}')
    echo "HASH: $hash" > /app/corpus/evil/evil4.txt
    echo -n "$body" >> /app/corpus/evil/evil4.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
