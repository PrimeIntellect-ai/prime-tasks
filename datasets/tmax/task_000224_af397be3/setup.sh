#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest scipy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/sim_data

    cat << 'EOF' > /home/user/spectro_sim.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <omp.h>

#define BINS 1000
#define NUM_PEAKS 50000

int main() {
    float spectrum[BINS];
    for(int i=0; i<BINS; i++) spectrum[i] = 0.0f;

    // Simulate concurrent accumulation causing non-deterministic floating point sums
    #pragma omp parallel for
    for(int p=0; p<NUM_PEAKS; p++) {
        // Create a pseudo-random lorentzian peak to add
        // Using a chaotic hash to avoid using non-thread-safe rand()
        unsigned int seed = p * 1337 + 1;
        seed ^= seed << 13;
        seed ^= seed >> 17;
        seed ^= seed << 5;

        float center = 400.0f + (seed % 200);
        float width = 5.0f + (seed % 15);
        float amplitude = (seed % 100) / 10.0f;

        for(int i=0; i<BINS; i++) {
            float diff = (float)i - center;
            float val = amplitude / (1.0f + (diff*diff)/(width*width));

            // Atomic float addition is non-associative and order depends on thread scheduling
            #pragma omp atomic
            spectrum[i] += val;
        }
    }

    for(int i=0; i<BINS; i++) {
        printf("%f\n", spectrum[i]);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
