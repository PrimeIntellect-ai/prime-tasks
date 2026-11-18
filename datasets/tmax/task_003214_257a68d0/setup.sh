#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc make sqlite3
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create voicemail.wav with specific metadata
    ffmpeg -f lavfi -i sine=frequency=1000:duration=1 -metadata artist="id,filename,sample_rate,channels,bit_depth,is_safe" /app/voicemail.wav

    # Populate clean corpus
    for i in $(seq 1 10); do
        ffmpeg -f lavfi -i sine=frequency=440:duration=0.1 /app/corpus/clean/clean$i.wav
    done

    # Populate evil corpus
    for i in $(seq 1 10); do
        dd if=/dev/urandom of=/app/corpus/evil/bad$i.wav bs=1024 count=1
    done

    # Create user
    useradd -m -s /bin/bash user || true

    # Create skeleton C file
    cat << 'EOF' > /home/user/wav_validator.c
#include <stdio.h>

int main(int argc, char *argv[]) {
    // TODO: implement WAV validation
    return 0;
}
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
