#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang build-essential
    pip3 install pytest

    # Create C library project
    mkdir -p /home/user/libtrajectory
    cat << 'EOF' > /home/user/libtrajectory/trajectory.c
#include "trajectory.h"
#include <math.h>

int check_trajectory(int x1, int y1, int x2, int y2) {
    double dist = sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2));
    return dist <= 2.0;
}
EOF

    cat << 'EOF' > /home/user/libtrajectory/trajectory.h
#ifndef TRAJECTORY_H
#define TRAJECTORY_H

int check_trajectory(int x1, int y1, int x2, int y2);

#endif
EOF

    cat << 'EOF' > /home/user/libtrajectory/Makefile
libtrajectory.so: trajectory.c
	gcc -shared -o libtrajectory.so trajectory.c -lm
EOF

    # Create dummy video
    mkdir -p /app
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=10 -r 30 /app/camera_feed.mp4

    # Create corpora
    mkdir -p /app/corpora/clean /app/corpora/evil
    cat << 'EOF' > /app/corpora/clean/1.txt
0,0
1,1
2,2
EOF
    cat << 'EOF' > /app/corpora/clean/2.txt
5,5
6,5
6,6
EOF

    cat << 'EOF' > /app/corpora/evil/1.txt
0,0
10,10
20,20
EOF
    cat << 'EOF' > /app/corpora/evil/2.txt
0,0
0,5
0,10
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
