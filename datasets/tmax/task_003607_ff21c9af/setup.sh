#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        git \
        gcc \
        python3-opencv

    pip3 install pytest numpy

    mkdir -p /app
    cd /app

    # 1. Generate Video
    cat << 'EOF' > make_video.py
import cv2
import numpy as np

frames = 32
width, height = 64, 64
fps = 10

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/incident_feed.mp4', fourcc, fps, (width, height))

bright_frames = {0, 2, 5, 7, 8, 12, 15, 18, 19, 22, 25, 27, 28, 30, 31}

for i in range(frames):
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    if i in bright_frames:
        frame[0:10, 0:10] = (255, 255, 255)
    out.write(frame)

out.release()
EOF
    python3 make_video.py
    rm make_video.py

    # 2. Generate Memory Dump
    dd if=/dev/urandom of=/app/coredump.raw bs=1M count=1
    echo -n "SALT_START=Xk9pQ2mNw8Rtz1L4_SALT_END" >> /app/coredump.raw
    dd if=/dev/urandom bs=1M count=1 >> /app/coredump.raw

    # 3. Create Git Repo
    mkdir -p /app/query_service
    cd /app/query_service
    git init
    git config user.name "Dev"
    git config user.email "dev@securecam.local"

    cat << 'EOF' > compute_query.py
import sys

def compute(input_val, key_hex, salt):
    return (input_val ^ int(key_hex, 16)) + sum(ord(c) for c in salt)

if __name__ == '__main__':
    print(compute(int(sys.argv[1]), sys.argv[2], sys.argv[3]))
EOF
    git add compute_query.py
    git commit -m "Initial working version of query logic"

    cat << 'EOF' > compute_query.py
import sys

def compute(input_val, key_hex, salt):
    return (input_val | int(key_hex, 16)) - sum(ord(c) for c in salt)

if __name__ == '__main__':
    print(compute(int(sys.argv[1]), sys.argv[2], sys.argv[3]))
EOF
    git add compute_query.py
    git commit -m "Update compute logic to improve performance"

    # 4. Create Oracle Binary
    cd /app
    cat << 'EOF' > oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    unsigned int input_val = (unsigned int)strtoul(argv[1], NULL, 10);
    unsigned int key = 0xa589325b;
    unsigned int salt_sum = 1354;
    unsigned int res = (input_val ^ key) + salt_sum;
    printf("%u\n", res);
    return 0;
}
EOF
    gcc -O2 oracle.c -o oracle_query
    strip oracle_query
    rm oracle.c

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
