#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/calibrator.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    double val = atof(argv[1]);
    // The proprietary calibration formula:
    double calibrated = (val * 1.045) + sin(val) * 2.1;
    printf("%f\n", calibrated);
    return 0;
}
EOF

    gcc -O2 /app/calibrator.c -o /app/calibrator -lm
    strip /app/calibrator
    chmod +x /app/calibrator
    rm /app/calibrator.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
