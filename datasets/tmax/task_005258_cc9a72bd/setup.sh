#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        ffmpeg \
        socat \
        netcat-openbsd \
        curl \
        imagemagick

    pip3 install pytest numpy opencv-python-headless

    mkdir -p /home/user/experiment
    mkdir -p /app

    cat << 'EOF' > /home/user/experiment/mc_sim.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 4) {
        printf("Error: Need 3 arguments\n");
        return 1;
    }
    int f0 = atoi(argv[1]);
    int f1 = atoi(argv[2]);
    int f2 = atoi(argv[3]);

    int total = f0 + f1 + f2;
    if (total == 0) total = 1;

    // Simulate Monte Carlo steady state output
    printf("{\"steady_state\": {\"node0\": %.2f, \"node1\": %.2f, \"node2\": %.2f}}\n", 
           (double)f0/total, (double)f1/total, (double)f2/total);
    return 0;
}
EOF

    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np

width, height = 400, 400
fps = 30
duration = 10
total_frames = fps * duration

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/particle_experiment.mp4', fourcc, fps, (width, height))

def get_blinks(num, total):
    return [int(i * total / num) for i in range(num)]

b0 = get_blinks(5, total_frames)
b1 = get_blinks(8, total_frames)
b2 = get_blinks(12, total_frames)

for i in range(total_frames):
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    if i in b0:
        cv2.circle(frame, (100, 100), 10, (255, 255, 255), -1)
    if i in b1:
        cv2.circle(frame, (300, 100), 10, (255, 255, 255), -1)
    if i in b2:
        cv2.circle(frame, (200, 300), 10, (255, 255, 255), -1)
    out.write(frame)

out.release()
EOF

    python3 /tmp/generate_video.py
    rm /tmp/generate_video.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
