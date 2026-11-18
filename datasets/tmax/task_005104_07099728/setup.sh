#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo curl
    pip3 install pytest

    mkdir -p /home/user/src /home/user/bin /home/user/data

    cat << 'EOF' > /home/user/src/extractor.c
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    int n = atoi(argv[1]);
    for (int i = 0; i < n; i++) {
        double t = (double)i / n;
        // Signal with 10 Hz (kept) and 100 Hz (filtered out) components
        double val = sin(2 * M_PI * 10 * t) + 0.5 * sin(2 * M_PI * 100 * t);
        printf("%f\n", val);
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
