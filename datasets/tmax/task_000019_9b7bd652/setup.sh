#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-opencv build-essential cmake
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/project

    # Generate calibration video
    cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/calibration.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
for t in range(100):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    x = 10 + 5 * t
    y = 100 + 2 * t + t * t
    if y >= 0 and y + 4 < 480 and x >= 0 and x + 4 < 640:
        cv2.rectangle(frame, (x, y), (x+4, y+4), (255, 255, 255), -1)
    out.write(frame)
out.release()
EOF
    python3 /app/generate_video.py

    # Create oracle predictor
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int t = atoi(argv[1]);
    long long x = 12LL + 5LL * t;
    long long y = 102LL + 2LL * t + (long long)t * t;
    printf("%lld %lld\n", x, y);
    return 0;
}
EOF
    gcc -O2 /app/oracle.c -o /app/oracle_predictor
    chmod +x /app/oracle_predictor

    # Create CMake project
    cat << 'EOF' > /home/user/project/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(TrajectoryPredictor C)

add_library(traj_lib SHARED traj.c)
add_executable(predictor main.c)

# Intentionally broken: missing target_link_libraries and RPATH setup
EOF

    cat << 'EOF' > /home/user/project/traj.c
#include <stdio.h>

void get_position(int t, int *x, int *y) {
    // TODO: implement based on video analysis
    *x = 0;
    *y = 0;
}
EOF

    cat << 'EOF' > /home/user/project/main.c
#include <stdio.h>
#include <stdlib.h>

extern void get_position(int t, int *x, int *y);

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <t>\n", argv[0]);
        return 1;
    }
    int t = atoi(argv[1]);
    int x, y;
    get_position(t, &x, &y);
    printf("%d %d\n", x, y);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
