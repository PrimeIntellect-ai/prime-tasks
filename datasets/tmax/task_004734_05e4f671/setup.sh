#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/simulator.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <math.h>
#include <time.h>

int main(int argc, char *argv[]) {
    double x = 0.0, y = 0.0;
    int opt;
    while ((opt = getopt(argc, argv, "x:y:")) != -1) {
        switch (opt) {
            case 'x': x = atof(optarg); break;
            case 'y': y = atof(optarg); break;
        }
    }

    // Seed random number generator
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    srand(ts.tv_nsec ^ (getpid() << 16));

    // True optimal is x=7.5, y=3.2
    double base_time = pow(x - 7.5, 2) + pow(y - 3.2, 2) + 5.0;

    // Add small noise to enable variance for the t-test
    double noise = ((double)rand() / RAND_MAX) * 0.5 - 0.25;
    double actual_time = base_time + noise;

    if (actual_time < 0.1) actual_time = 0.1;

    printf("Runtime: %.4f\n", actual_time);
    return 0;
}
EOF

    chmod -R 777 /home/user
