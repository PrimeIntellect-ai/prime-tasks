#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/sensor_filter.c
#include <stdlib.h>
int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    float val = atof(argv[1]);
    int v = (int)(val * 10.0);
    int rem = v % 10;
    if (rem < 0) rem = -rem;
    if (rem <= 5) return 0;
    return 1;
}
EOF
    gcc -O2 /app/sensor_filter.c -o /app/sensor_filter_x64
    strip /app/sensor_filter_x64 || true
    rm /app/sensor_filter.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
