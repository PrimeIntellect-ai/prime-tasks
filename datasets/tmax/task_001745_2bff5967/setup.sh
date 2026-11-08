#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc time coreutils
    pip3 install pytest

    mkdir -p /home/user/math_project
    cat << 'EOF' > /home/user/math_project/math_ops.c
#include <math.h>

double compute_series(int n) {
    double sum = 0.0;
    for (int i = 1; i <= n; i++) {
        sum += sin((double)i) * cos((double)i);
    }
    return sum;
}
EOF

    cat << 'EOF' > /home/user/math_project/main.c
#include <stdio.h>
#include <stdlib.h>

extern double compute_series(int n);

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int n = atoi(argv[1]);
    double result = compute_series(n);
    printf("%.6f\n", result);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
