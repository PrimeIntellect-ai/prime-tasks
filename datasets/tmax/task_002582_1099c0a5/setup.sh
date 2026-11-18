#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl
    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /app/config /app/bin

    cat << 'EOF' > /app/extractor.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <wav_file>\n", argv[0]);
        return 1;
    }
    // Simulate audio extraction
    // In a real scenario, this would parse the audio fixture
    printf("DURATION=12|TRANSCRIPT=PIPELINE_OK_992\n");
    return 0;
}
EOF
    chmod +x /app/extractor.c

    echo "RIFF....WAVEfmt ........" > /app/ci_diagnostic.wav

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
