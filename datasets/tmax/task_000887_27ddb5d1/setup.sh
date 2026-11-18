#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils golang
    pip3 install pytest jupyter h5py numpy

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *seq = argv[1];
    int len = strlen(seq);
    if (len < 2) {
        printf("0.000000\n");
        return 0;
    }

    // Values: A = -1.0, T = -1.0, C = 1.5, G = 1.5
    double sum = 0.0;
    for (int i = 0; i < len; i++) {
        double val = 0.0;
        if (seq[i] == 'A' || seq[i] == 'T') val = -1.0;
        else if (seq[i] == 'C' || seq[i] == 'G') val = 1.5;

        // Trapezoidal integration weights: 0.5 for ends, 1.0 for middle
        double weight = (i == 0 || i == len - 1) ? 0.5 : 1.0;
        sum += val * weight;
    }

    printf("%.6f\n", sum);
    return 0;
}
EOF

    gcc -O2 /tmp/oracle.c -o /app/seq_evaluator
    strip /app/seq_evaluator
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
