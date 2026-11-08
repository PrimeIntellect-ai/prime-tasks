#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang binutils
    pip3 install pytest scikit-learn statsmodels pandas numpy

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle_scorer.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 5) return 1;
    long long a = atoll(argv[1]);
    long long b = atoll(argv[2]);
    long long c = atoll(argv[3]);
    long long d = atoll(argv[4]);

    long long score = 42 * a - 15 * b + 7 * c + 8 * d + 123;
    int category = 0;
    if (score > 500) {
        category = 1;
    } else if (score < 0) {
        category = 2;
    }

    printf("%lld %d\n", score, category);
    return 0;
}
EOF

    gcc -O2 /tmp/oracle_scorer.c -o /app/oracle_scorer
    strip /app/oracle_scorer
    rm /tmp/oracle_scorer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
