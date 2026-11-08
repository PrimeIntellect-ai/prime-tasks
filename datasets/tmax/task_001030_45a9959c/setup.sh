#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential espeak ffmpeg git wget
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak -w /tmp/temp.wav "Turn on the living room lights."
    ffmpeg -i /tmp/temp.wav -ar 16000 -ac 1 -c:a pcm_s16le /app/command.wav
    rm /tmp/temp.wav

    # Create and compile the oracle binary
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>

float relu(float x) { return x > 0 ? x : 0; }

int main() {
    float x[5];
    if (scanf("%f %f %f %f %f", &x[0], &x[1], &x[2], &x[3], &x[4]) != 5) return 1;

    float w[5][3] = {
        {0.5, -0.2, 0.1},
        {-0.1, 0.8, -0.4},
        {1.0, 0.0, 0.5},
        {-0.5, 0.5, 0.5},
        {0.0, -1.0, 1.0}
    };

    float y[3] = {0, 0, 0};
    for(int j=0; j<3; j++) {
        for(int i=0; i<5; i++) {
            y[j] += x[i] * w[i][j];
        }
        y[j] = relu(y[j]);
    }

    printf("%.4f %.4f %.4f\n", y[0], y[1], y[2]);
    return 0;
}
EOF

    gcc -O3 /tmp/oracle.c -o /app/oracle_projector
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
