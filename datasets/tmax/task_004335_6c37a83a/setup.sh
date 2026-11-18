#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind gdb
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/simulator.c
#include <stdio.h>
#include <stdlib.h>

void simulate_decay() {
    // Starting energy is 2^25. In standard IEEE 754 32-bit floats, 
    // the step size between representable numbers at this magnitude is 2.0.
    float energy = 33554432.0f; 
    float decay_rate = 1.0f;

    printf("Starting simulation...\n");

    // BUG: Because energy is 33554432.0f, subtracting 1.0f yields 33554432.0f
    // due to 24-bit mantissa precision limits. This loop never terminates.
    while (energy > 0.0f) {
        // Simulating state tracking which leaks memory if it loops infinitely
        void* state_tracker = malloc(64);
        if (!state_tracker) {
            printf("OOM!\n");
            exit(1);
        }

        energy -= decay_rate;
    }

    printf("Simulation complete.\n");
}

int main() {
    simulate_decay();
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
