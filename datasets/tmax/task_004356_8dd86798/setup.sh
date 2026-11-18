#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils libc6-dev gawk
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create and compile anomaly_scorer
    cat << 'EOF' > /tmp/scorer.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 4) return 1;
    long N = atol(argv[1]);
    long E = atol(argv[2]);
    long R = atol(argv[3]);
    float raw = (E * 2.5 + R * 4.0) / (N > 0 ? (float)N : 1.0);
    float prob = 1.0 / (1.0 + exp(-raw));
    printf("%.2f\n", prob);
    return 0;
}
EOF
    gcc -O2 /tmp/scorer.c -lm -o /app/anomaly_scorer
    strip /app/anomaly_scorer
    rm /tmp/scorer.c

    # Generate Clean Corpus (N=20, E=1, R=1)
    # raw = 6.5 / 20 = 0.325 -> prob ~ 0.58 (< 0.75)
    for i in $(seq 1 20); do
        echo "1678886400,EVENT,404,1" >> /app/corpus/clean/log1.csv
    done

    # Generate Evil Corpus (N=5, E=4, R=10)
    # raw = 50.0 / 5 = 10.0 -> prob ~ 1.00 (> 0.75)
    cat << 'EOF' > /app/corpus/evil/mal1.csv
1678886400,EVENT,500,10
1678886401,EVENT,501,2
1678886402,EVENT,502,3
1678886403,EVENT,503,4
1678886404,EVENT,0,1
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
