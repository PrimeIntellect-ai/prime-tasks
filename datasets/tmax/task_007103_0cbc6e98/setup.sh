#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/sensor_aggregator.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <file>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("fopen");
        return 1;
    }

    double sum = 0;
    double sum_sq = 0;
    int count = 0;
    double val;

    while (fscanf(f, "%lf", &val) == 1) {
        sum += val;
        sum_sq += val * val;
        count++;
    }
    fclose(f);

    if (count == 0) {
        printf("0.000000\n");
        return 0;
    }

    double mean = sum / count;
    // Naive variance formula: E[X^2] - (E[X])^2
    // Highly susceptible to catastrophic cancellation with large floats.
    double variance = (sum_sq / count) - (mean * mean);

    // variance can become slightly negative due to precision loss
    double stddev = sqrt(variance);

    printf("%f\n", stddev);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/Makefile
sensor_aggregator: sensor_aggregator.c
	gcc -O0 -g -o sensor_aggregator sensor_aggregator.c -lm
EOF

    make
    cp sensor_aggregator sensor_aggregator_buggy

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
