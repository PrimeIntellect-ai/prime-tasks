#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc python3-matplotlib
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/vol_estimator.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc != 4) return 1;
    uint32_t state = (uint32_t)atoi(argv[1]);
    int N = atoi(argv[2]);
    double R = atof(argv[3]);

    int count = 0;
    for (int i = 0; i < N; i++) {
        state = (1103515245U * state + 12345U) & 0x7FFFFFFF;
        double x = -R + (2.0 * R * (double)state) / 2147483648.0;

        state = (1103515245U * state + 12345U) & 0x7FFFFFFF;
        double y = -R + (2.0 * R * (double)state) / 2147483648.0;

        state = (1103515245U * state + 12345U) & 0x7FFFFFFF;
        double z = -R + (2.0 * R * (double)state) / 2147483648.0;

        if (x*x + y*y <= R*R && x*x + z*z <= R*R) {
            count++;
        }
    }
    printf("%d\n", count);
    return 0;
}
EOF
    gcc -O3 -s /tmp/vol_estimator.c -o /app/vol_estimator
    rm /tmp/vol_estimator.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
