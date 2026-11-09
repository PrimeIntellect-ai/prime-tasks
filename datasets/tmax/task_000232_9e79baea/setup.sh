#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc python3-opencv
    pip3 install pytest

    mkdir -p /app

    # Create the oracle C code
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    unsigned long hash = 0x5A5A;
    for (int i = 0; i < strlen(argv[1]); i++) {
        hash = ((hash << 4) ^ (hash >> 28) ^ argv[1][i]) & 0xFFFFFFFF;
    }
    printf("%08lx\n", hash);
    return 0;
}
EOF

    # Compile and strip the oracle
    gcc -O2 -o /app/auth_oracle /tmp/oracle.c
    strip /app/auth_oracle

    # Create the video generation script
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/network_traffic.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (800, 600))
for i in range(60):
    img = np.zeros((600, 800, 3), dtype=np.uint8)
    if i == 30:
        text = """POST /api/v1/authenticate HTTP/1.1
Host: internal-auth.local
Cookie: Session-ID=root_8f99a1b2c3d4e5f6; theme=dark
X-Exploit-Payload: true"""
        y0, dy = 50, 30
        for j, line in enumerate(text.split('\n')):
            y = y0 + j*dy
            cv2.putText(img, line, (10, y), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1, cv2.LINE_AA)
    else:
        cv2.putText(img, f"Frame {i} - Normal Traffic", (10, 50), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1)
    out.write(img)
out.release()
EOF

    # Generate the video
    python3 /tmp/gen_video.py

    # Clean up
    rm /tmp/oracle.c /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
