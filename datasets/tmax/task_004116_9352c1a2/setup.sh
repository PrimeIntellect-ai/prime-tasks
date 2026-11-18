#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest grpcio grpcio-tools

    mkdir -p /home/user/audio_tool
    mkdir -p /home/user/service
    mkdir -p /app

    cat << 'EOF' > /home/user/audio_tool/main.c
// Missing stdio.h and stdlib.h
extern void process_audio(const char* filepath);

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    process_audio(argv[1]);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/audio_tool/process.c
#include <math.h>
#include <stdio.h>

void process_audio(const char* filepath) {
    // Mock processing
    double val = sqrt(16.0);
    printf("EVENTS: %.0f\n", val);
}
EOF

    cat << 'EOF' > /home/user/audio_tool/Makefile
analyzer: main.o process.o
    gcc -o analyzer main.o process.o

main.o: main.c
    gcc -c main.c

process.o: process.c
    gcc -c process.c
EOF

    # Create a dummy wav file
    echo "RIFF....WAVEfmt .....data...." > /app/test_audio.wav

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
