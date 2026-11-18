#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y ffmpeg socat netcat-openbsd gcc make

    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=10:size=854x480:rate=30 /app/drone_footage.mp4

    mkdir -p /home/user/analyzer

    cat << 'EOF' > /home/user/analyzer/frame_analyzer.c
#include <stdio.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <raw_rgb_file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        printf("Failed to open file\n");
        return 1;
    }

    int width = 854;
    int height = 480;
    int size = width * height * 3;

    unsigned char *buffer = malloc(size - 1); // Intentional bug
    if (!buffer) return 1;

    fread(buffer, 1, size, f);
    fclose(f);

    long long sum = 0;
    for (int i = 0; i < size; i++) {
        sum += buffer[i];
    }

    printf("%lld\n", sum % 256);
    free(buffer);

    return 0;
}
EOF

    cat << 'EOF' > /home/user/analyzer/Makefile
all:
	gcc frame_analyzer.c -o frame_analyzer
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
