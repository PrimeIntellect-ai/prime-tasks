#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc libc6-dev
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Generate a dummy input video
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -c:v libx264 /app/input_video.mp4

    # Create oracle C source
    cat << 'EOF' > /app/oracle_hasher.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

uint64_t compute_hash(const char *filename) {
    FILE *f = fopen(filename, "rb");
    if (!f) exit(1);
    uint8_t pixels[64][64];
    fread(pixels, 1, 4096, f);
    fclose(f);

    uint64_t A[64];
    uint64_t G = 0;

    for (int br = 0; br < 8; br++) {
        for (int bc = 0; bc < 8; bc++) {
            uint32_t sum = 0;
            for (int pr = 0; pr < 8; pr++) {
                for (int pc = 0; pc < 8; pc++) {
                    sum += pixels[br * 8 + pr][bc * 8 + pc];
                }
            }
            int b = br * 8 + bc;
            A[b] = sum / 64;
            G += A[b];
        }
    }

    uint64_t Ag = G / 64;
    uint64_t hash = 0;
    for (int b = 0; b < 64; b++) {
        if (A[b] > Ag) {
            hash |= (1ULL << b);
        }
    }
    return hash;
}

int main(int argc, char **argv) {
    if (argc != 3) return 1;
    uint64_t h1 = compute_hash(argv[1]);
    uint64_t h2 = compute_hash(argv[2]);
    int dist = 0;
    uint64_t xor = h1 ^ h2;
    for (int i = 0; i < 64; i++) {
        if ((xor >> i) & 1) dist++;
    }
    printf("Hash1: %016llx\n", (unsigned long long)h1);
    printf("Hash2: %016llx\n", (unsigned long long)h2);
    printf("Distance: %d\n", dist);
    return 0;
}
EOF

    # Compile the oracle
    gcc -O2 /app/oracle_hasher.c -o /app/oracle_hasher

    # Create the user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
