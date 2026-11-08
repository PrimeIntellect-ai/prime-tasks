#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++ golang-go bc python3-opencv
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Generate video
    cat << 'EOF' > /tmp/gen_vid.py
import os
import subprocess
import cv2
import numpy as np

text = "pkgA>=1.0.0,<2.0.0\npkgB>=1.5.0\npkgA<=1.9.0\npkgC>=0.0.1\n"
bits = ''.join(format(ord(c), '08b') for c in text)

os.makedirs('/tmp/frames', exist_ok=True)
for i, bit in enumerate(bits):
    color = 255 if bit == '1' else 0
    img = np.full((100, 100, 3), color, dtype=np.uint8)
    cv2.imwrite(f"/tmp/frames/frame_{i:04d}.png", img)

subprocess.run(["ffmpeg", "-y", "-framerate", "30", "-i", "/tmp/frames/frame_%04d.png", "-c:v", "libx264", "-pix_fmt", "yuv420p", "/app/signal.mp4"])
EOF
    python3 /tmp/gen_vid.py
    rm -rf /tmp/frames /tmp/gen_vid.py

    # Create resolver.go
    cat << 'EOF' > /home/user/resolver.go
package main
import (
    "fmt"
)
func main() {
    fmt.Println("pkgA: 1.9.0")
    fmt.Println("pkgB: 1.5.0")
    fmt.Println("pkgC: 0.0.1")
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
