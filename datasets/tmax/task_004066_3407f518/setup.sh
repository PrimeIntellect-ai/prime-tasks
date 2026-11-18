#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libomp-dev espeak socat netcat-openbsd ffmpeg curl
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/directive.wav "The secret seed is eight eight four two."

    mkdir -p /home/user
    cat << 'EOF' > /home/user/mc_sim.c
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    int seed = atoi(argv[1]);
    int threads = atoi(argv[2]);
    omp_set_num_threads(threads);

    long long num_samples = 100000000;
    long long inside_circle = 0;

    #pragma omp parallel reduction(+:inside_circle)
    {
        unsigned int local_seed = seed + omp_get_thread_num();
        #pragma omp for
        for (long long i = 0; i < num_samples; i++) {
            double x = (double)rand_r(&local_seed) / RAND_MAX;
            double y = (double)rand_r(&local_seed) / RAND_MAX;
            if (x * x + y * y <= 1.0) {
                inside_circle++;
            }
        }
    }

    double pi = 4.0 * inside_circle / num_samples;
    printf("%.5f\n", pi);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
