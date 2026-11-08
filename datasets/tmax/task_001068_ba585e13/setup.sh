#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Create the legacy C code
    cat << 'EOF' > /app/legacy_analyzer.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    uint32_t sum = 0;
    uint8_t max_val = 0;
    int c;
    while ((c = fgetc(f)) != EOF) {
        sum += c;
        if (c > max_val) max_val = c;
    }
    fclose(f);
    // Numerical instability: if max_val == 255, this divides by zero and crashes (SIGFPE)
    uint32_t score = sum / (255 - max_val);
    printf("%u\n", score);
    return 0;
}
EOF

    # Compile the legacy binary
    gcc -O2 -o /app/legacy_analyzer /app/legacy_analyzer.c
    rm /app/legacy_analyzer.c

    # Generate the test video
    cat << 'EOF' > /tmp/gen_video.py
import os

width, height = 320, 240
frames = 72

with open('/tmp/raw.gray', 'wb') as f:
    for i in range(frames):
        # Generate random bytes, cap at 200 to avoid accidental 255
        b = bytearray(os.urandom(width * height))
        b = bytearray([x if x <= 200 else 200 for x in b])

        # Frame 42 must contain a pure white pixel (255)
        if i == 42:
            b[0] = 255

        f.write(b)
EOF
    python3 /tmp/gen_video.py

    # Encode raw grayscale to lossless mp4
    ffmpeg -y -f rawvideo -pixel_format gray -video_size 320x240 -framerate 24 \
        -i /tmp/raw.gray -c:v libx264 -crf 0 -preset ultrafast /app/test_sequence.mp4

    rm /tmp/gen_video.py /tmp/raw.gray

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
