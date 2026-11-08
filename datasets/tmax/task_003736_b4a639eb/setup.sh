#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc ffmpeg
    pip3 install pytest

    mkdir -p /home/user/video_toolkit
    mkdir -p /app

    # Create dummy mp4 video
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -c:v libx264 -pix_fmt yuv420p /app/traffic.mp4

    # Create C source files for shared libraries
    cat << 'EOF' > /tmp/libprocess_v1.c
#include <unistd.h>
void process_frame() {
    usleep(200000); // simulate high CPU / slow processing
}
EOF

    cat << 'EOF' > /tmp/libprocess_v2.c
void process_frame() {
    // optimized, returns immediately
}
EOF

    # Compile shared libraries
    gcc -shared -fPIC -o /home/user/video_toolkit/libprocess_v1.so /tmp/libprocess_v1.c
    gcc -shared -fPIC -o /home/user/video_toolkit/libprocess_v2_opt.so /tmp/libprocess_v2.c

    # Create frame_processor.c
    cat << 'EOF' > /home/user/video_toolkit/frame_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

extern void process_frame();

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <file>\n", argv[0]);
        return 1;
    }

    struct stat st;
    if (stat(argv[1], &st) == 0) {
        // Artificially segfault if size is a multiple of 7
        if (st.st_size % 7 == 0) {
            volatile char *p = NULL;
            *p = 'a';
        }
    }

    process_frame();
    printf("Processed %s\n", argv[1]);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
