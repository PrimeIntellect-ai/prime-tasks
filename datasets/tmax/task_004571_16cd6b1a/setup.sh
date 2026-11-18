#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc libc-dev
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_video.py
import sys
import random

w, h = 1920, 1080
fps = 30
duration = 10
total_frames = fps * duration

# Exactly 14 frames are solid red
red_frame_indices = set(random.sample(range(total_frames), 14))

for i in range(total_frames):
    if i in red_frame_indices:
        # red frame: RGB 255, 0, 0
        frame = b'\xff\x00\x00' * (w * h)
    else:
        # black frame
        frame = b'\x00\x00\x00' * (w * h)
    sys.stdout.buffer.write(frame)
EOF

    python3 /tmp/gen_video.py | ffmpeg -y -f rawvideo -pixel_format rgb24 -video_size 1920x1080 -framerate 30 -i pipe:0 -c:v libx264 -pix_fmt yuv420p /app/deploy_recording.mp4
    rm /tmp/gen_video.py

    mkdir -p /home/user/src
    cat << 'EOF' > /home/user/src/analyze_frame.c
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int width;
    int height;
    unsigned char **rows;
} CustomImage;

int main(int argc, char **argv) {
    int w = 1920, h = 1080;

    CustomImage *img = malloc(sizeof(CustomImage));
    img->width = w;
    img->height = h;
    img->rows = malloc(h * sizeof(unsigned char *));

    // BUG 1: Allocates w instead of w * 3 for RGB24
    for(int i = 0; i < h; i++) {
        img->rows[i] = malloc(w); 
    }

    long long total_red = 0;

    for(int i = 0; i < h; i++) {
        // BUG 2: Reading w*3 bytes into a w-byte buffer
        if (fread(img->rows[i], 1, w * 3, stdin) != w * 3) {
            return 1;
        }
        for(int j = 0; j < w; j++) {
            total_red += img->rows[i][j * 3]; // Read red channel
        }
    }

    int avg_red = total_red / (w * h);
    printf("%d\n", avg_red);

    // BUG 3: Memory leak (not freeing rows or struct)
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
