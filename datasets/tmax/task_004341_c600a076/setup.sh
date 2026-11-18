#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git python3-opencv
    pip3 install pytest

    mkdir -p /app/diag_tools
    mkdir -p /opt/oracle

    # Generate video
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

binary_sequence = "01001000011001010110110001101100011011110010000001010111011011110111001001101100011001000010000100000000"
out = cv2.VideoWriter('/app/diagnostic_blink.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10.0, (100, 100))
for bit in binary_sequence:
    color = 255 if bit == '1' else 0
    frame = np.full((100, 100, 3), color, dtype=np.uint8)
    out.write(frame)
out.release()
EOF
    python3 /tmp/gen_video.py

    # Create buggy decode.py
    cat << 'EOF' > /app/diag_tools/decode.py
import sys

SECRET_KEY = "" # To be recovered

def decode_bits(bits):
    if len(bits) % 8 != 0:
        bits = bits + "0" * (8 - (len(bits) % 8))

    chars = []
    # BUG: Off-by-one error in chunking. It slices i:i+7 instead of i:i+8
    for i in range(0, len(bits), 8):
        byte_str = bits[i:i+7] 
        if byte_str:
            chars.append(chr(int(byte_str, 2)))

    return "".join(chars) + SECRET_KEY

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    print(decode_bits(sys.argv[1]), end="")
EOF

    # Setup Git repository
    cd /app/diag_tools
    git init
    git config user.name "Admin"
    git config user.email "admin@example.com"
    git add decode.py
    git commit -m "Add initial structure and decode.py"

    sed -i 's/SECRET_KEY = "" # To be recovered/SECRET_KEY = "diag_enc_9942a_prod" # To be recovered/' decode.py
    git add decode.py
    git commit -m "Add SECRET_KEY to decode.py"

    sed -i 's/SECRET_KEY = "diag_enc_9942a_prod" # To be recovered/SECRET_KEY = "" # To be recovered/' decode.py
    git add decode.py
    git commit -m "Accidental deletion of SECRET_KEY"

    # Create oracle script
    cat << 'EOF' > /opt/oracle/decode_oracle.py
import sys

SECRET_KEY = "diag_enc_9942a_prod"

def decode_bits(bits):
    if len(bits) % 8 != 0:
        bits = bits + "0" * (8 - (len(bits) % 8))

    chars = []
    for i in range(0, len(bits), 8):
        byte_str = bits[i:i+8]
        if byte_str:
            chars.append(chr(int(byte_str, 2)))

    return "".join(chars) + SECRET_KEY

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    print(decode_bits(sys.argv[1]), end="")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /opt
