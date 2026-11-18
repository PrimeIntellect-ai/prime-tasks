#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/simulator.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    double r = atof(argv[1]);
    double y = 0.1;
    double t = 0.0;
    double dt = 0.01;
    double t_end = 5.0;

    while (t < t_end) {
        double dydt = r * y * (1.0 - y / 10.0);

        // BUGGY LINE BELOW
        dt = 0.01 * (1.0 + fabs(dydt));

        if (t + dt > t_end) {
            dt = t_end - t;
        }
        y = y + dydt * dt;
        t = t + dt;
    }

    printf("%.6f\n", y);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/params.csv
seq1,0.2
seq2,1.8
seq3,-0.5
seq4,2.5
seq5,0.8
EOF

    cat << 'EOF' > /home/user/sequences.fasta
>seq1
ATGCGTA
CGTACGT
>seq2
GGGGCCCC
TTTTAAAA
>seq3
ATATATAT
>seq4
CGTACGTA
CGTACGTA
>seq5
AAAA
CCCC
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
