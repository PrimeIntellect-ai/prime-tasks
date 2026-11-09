#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y ffmpeg nginx netcat-openbsd

    # Create /app directory
    mkdir -p /app

    # Generate the video fixture
    ffmpeg -f lavfi -i "color=c=red:s=640x480:r=30:d=5" \
           -f lavfi -i "color=c=black:s=640x480:r=30:d=1.4" \
           -f lavfi -i "color=c=blue:s=640x480:r=30:d=3" \
           -filter_complex "[0:v][1:v][2:v]concat=n=3:v=1:a=0[outv]" \
           -map "[outv]" -c:v libx264 /app/ui_test.mp4

    # Create the oracle signer script
    cat << 'EOF' > /app/oracle_signer
#!/usr/bin/env python3
import sys

if len(sys.argv) != 2:
    sys.exit(1)

input_str = sys.argv[1]
secret_key = 42

out = ""
parity = 0
for char in input_str:
    val = ord(char)
    xor_val = val ^ secret_key
    out += f"{xor_val:02X}"
    parity ^= val

out += f"{parity:02X}"
print(out)
EOF
    chmod +x /app/oracle_signer

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
