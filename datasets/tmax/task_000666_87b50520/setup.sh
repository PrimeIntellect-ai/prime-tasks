#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc gcc-aarch64-linux-gnu libc6-dev libc6-dev-arm64-cross ffmpeg
    pip3 install pytest

    mkdir -p /home/user/src /home/user/build
    cat << 'EOF' > /home/user/src/checksum.h
#include <stdint.h>
#include <stddef.h>
uint32_t calculate_checksum(const uint8_t *data, size_t len);
EOF

    cat << 'EOF' > /home/user/src/checksum.c
#include "checksum.h"

uint32_t calculate_checksum(const uint8_t *data, size_t len) {
    uint32_t s1 = 1;
    uint32_t s2 = 0;
    // BUG: <= len causes OOB read
    for (size_t i = 0; i <= len; i++) {
        s1 = (s1 + data[i]) % 65521;
        s2 = (s2 + s1) % 65521;
    }
    return (s2 << 16) | s1;
}
EOF

    cd /home/user/src
    go mod init video_pipeline

    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=1:size=320x240:rate=10 -c:v libx264 /app/test_video.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
