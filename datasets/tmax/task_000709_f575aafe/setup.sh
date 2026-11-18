#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/orbit_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main() {
    float S = 612.0f;
    float current = 10.0f;
    float next = 0.0f;

    while (1) {
        // Memory leak!
        float* temp_history = (float*)malloc(sizeof(float));
        *temp_history = current;

        next = 0.5f * (current + S / current);

        // Flawed convergence check (precision failure)
        if (current == next) {
            free(temp_history);
            break;
        }

        current = next;
        // Forgot to free temp_history here causing memory leak
    }

    printf("%.5f\n", current);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
