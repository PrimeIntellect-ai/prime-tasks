#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/detector.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 5) return 1;
    double v1 = atof(argv[1]);
    double v2 = atof(argv[2]);
    double v3 = atof(argv[3]);
    double curr = atof(argv[4]);

    double hist_avg = (v1 + v2 + v3) / 3.0;
    if (curr > (hist_avg * 1.5 + 2.5)) {
        printf("ANOMALY\n");
    } else {
        printf("NORMAL\n");
    }
    return 0;
}
EOF
    gcc /tmp/detector.c -o /app/detector.bin
    strip /app/detector.bin
    rm /tmp/detector.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
