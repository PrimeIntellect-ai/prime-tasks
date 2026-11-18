#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make git time
    pip3 install pytest

    mkdir -p /app
    touch /app/incident_stream.mp4

    mkdir -p /home/user/videod_repo
    cd /home/user/videod_repo

    git init
    git config --global user.email "dev@example.com"
    git config --global user.name "Dev"

    # Base Makefile
    cat << 'EOF' > Makefile
videod: main.c process.c
	gcc -o videod main.c process.c -I. -Wall
EOF

    # Header
    cat << 'EOF' > process.h
#ifndef PROCESS_H
#define PROCESS_H
int process_frame(unsigned char *frame_data, int width, int height);
#endif
EOF

    # Main file
    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include "process.h"

#define FRAME_SIZE (1920*1080*3)

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    // Simulate reading frames from the video file
    for(int i = 0; i < 300; i++) {
        unsigned char *frame = malloc(FRAME_SIZE);
        if (!frame) break;
        // Mocking dark frames for testing
        if (i > 100) frame[0] = 5; else frame[0] = 100;

        process_frame(frame, 1920, 1080);
    }
    return 0;
}
EOF

    # Good process.c
    cat << 'EOF' > process.c
#include <stdlib.h>
#include "process.h"

int process_frame(unsigned char *frame, int width, int height) {
    // Good Luma calculation
    float Y = 0.299 * frame[0] + 0.587 * frame[1] + 0.114 * frame[2];

    if (Y < 10.0) {
        // Anomaly detected
        free(frame);
        return -1;
    }

    free(frame);
    return 0;
}
EOF

    git add .
    git commit -m "Initial commit: Stable v1.0"
    git tag v1.0

    # Introduce 5 dummy commits
    for i in {1..5}; do
        echo "// Dummy $i" >> main.c
        git commit -am "Minor update $i"
    done

    # The Buggy Commit
    cat << 'EOF' > process.c
#include <stdlib.h>
#include "process.h"

int process_frame(unsigned char *frame, int width, int height) {
    // Bug: Typos in formula and missing free() on early return
    float Y = 0.299 * frame[0] + 0.587 * frame[1] - 0.114 * frame[2];

    if (Y < 10.0) {
        // Anomaly detected - LEAK HERE
        return -1;
    }

    free(frame);
    return 0;
}
EOF
    git commit -am "Optimize frame processing and error handling"

    # 3 more dummy commits
    for i in {6..8}; do
        echo "// Dummy $i" >> main.c
        git commit -am "Refactoring $i"
    done

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/videod_repo
    chmod -R 777 /home/user
    chmod -R 777 /app
