#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gcc make ffmpeg
    pip3 install pytest websockets

    mkdir -p /app

    cat << 'EOF' > /app/Makefile
libcore.so: core.c
	gcc -o libcore.so core.c
EOF

    cat << 'EOF' > /app/core.c
#include <math.h>

double process_value(double a, double b, double c, double x) {
    return (a * sin(x)) + (b * cos(x)) + (c * exp(-x));
}
EOF

    espeak -w /app/calibration.wav "Seven. Twenty-two. Eighty-one."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
