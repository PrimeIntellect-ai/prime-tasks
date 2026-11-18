#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick ffmpeg
    pip3 install pytest

    mkdir -p /opt/verifier
    cat << 'EOF' > /opt/verifier/oracle.py
#!/usr/bin/env python3
import sys

def recover(hex_str, index):
    if len(hex_str) != 48:
        return "ERROR"

    prefix = hex_str[:16]
    suffix = hex_str[32:]

    # Bytes 8-11 (chars 16-23)
    val1 = int(hex_str[16:24], 16)
    val1_fixed = (val1 - index) % (2**32)
    part1 = f"{val1_fixed:08x}"

    # Bytes 12-15 (chars 24-31)
    val2 = int(hex_str[24:32], 16)
    val2_fixed = val2 ^ 0xDEADBEEF
    part2 = f"{val2_fixed:08x}"

    print(prefix + part1 + part2 + suffix)

if __name__ == "__main__":
    recover(sys.argv[1], int(sys.argv[2]))
EOF
    chmod +x /opt/verifier/oracle.py

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_video.py
import os
import subprocess

message = "SPEC: Write a Python script at /home/user/recover.py that takes two args: a 48-character hex string and an integer index. Reverse this corruption: chars 16-23 (bytes 8-11, big-endian) had the index added (modulo 2^32). Chars 24-31 (bytes 12-15) were XORed with 0xDEADBEEF. Print the corrected 48-char hex string."
bits = ''.join(f"{ord(c):08b}" for c in message)

os.makedirs("/tmp/frames", exist_ok=True)
for i, bit in enumerate(bits):
    color = "white" if bit == "1" else "black"
    subprocess.run(["convert", "-size", "100x100", f"xc:{color}", f"/tmp/frames/frame_{i:04d}.png"], check=True)

subprocess.run([
    "ffmpeg", "-y", "-framerate", "30", "-i", "/tmp/frames/frame_%04d.png",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "/app/transmission.mp4"
], check=True)
EOF
    python3 /tmp/gen_video.py
    rm -rf /tmp/frames /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
