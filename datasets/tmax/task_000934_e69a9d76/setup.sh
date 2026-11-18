#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        g++ \
        make \
        cmake \
        cron \
        curl \
        binutils \
        wget \
        git

    pip3 install pytest requests

    # Create the scorer binary
    mkdir -p /app
    cat << 'EOF' > /tmp/scorer.c
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 3) {
        printf("Usage: %s <orig> <trans>\n", argv[0]);
        return 1;
    }
    // Dummy deterministic scoring
    int diff = strlen(argv[1]) - strlen(argv[2]);
    if (diff < 0) diff = -diff;
    float score = 1.0 - (diff * 0.1);
    if (score < 0.0) score = 0.1;
    printf("Score: %.2f\n", score);
    return 0;
}
EOF
    gcc -O2 /tmp/scorer.c -o /app/scorer
    strip /app/scorer
    rm /tmp/scorer.c
    chmod +x /app/scorer

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
