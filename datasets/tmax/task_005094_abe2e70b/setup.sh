#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils file
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/nanopore_scorer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char *seq = argv[1];
    int n = strlen(seq);
    if (argc != n + 2) return 1;

    double expected[n];
    for (int i = 0; i < n; i++) {
        if (seq[i] == 'A') expected[i] = 1.0;
        else if (seq[i] == 'C') expected[i] = -1.0;
        else if (seq[i] == 'G') expected[i] = 0.5;
        else if (seq[i] == 'T') expected[i] = -0.5;
        else expected[i] = 0.0;
    }

    double raw[n];
    for (int i = 0; i < n; i++) {
        raw[i] = atof(argv[2 + i]);
    }

    double filtered[n];
    for (int i = 0; i < n; i++) {
        if (i == 0) {
            filtered[i] = raw[i];
        } else if (i == 1) {
            filtered[i] = 0.75 * raw[i] + 0.25 * raw[i-1];
        } else {
            filtered[i] = 0.5 * raw[i] + 0.25 * raw[i-1] + 0.25 * raw[i-2];
        }
    }

    double distance = 0.0;
    for (int i = 0; i < n; i++) {
        double diff = filtered[i] - expected[i];
        distance += diff * diff;
    }
    distance = sqrt(distance);

    printf("%.4f\n", distance);
    return 0;
}
EOF
    gcc -O2 -o /app/nanopore_scorer /app/nanopore_scorer.c -lm
    strip /app/nanopore_scorer
    rm /app/nanopore_scorer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
