#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/calibrator.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int recursive_sum(int *arr, int len) {
    if (len <= 0) return 0;
    // BUG 1: Recursion doesn't decrement length, causes stack overflow
    return arr[0] + recursive_sum(arr + 1, len);
}

double find_root(double val) {
    if (val <= 0) return 0;
    double guess = val / 2.0;

    // BUG 2: Exact float comparison causes convergence failure (infinite loop)
    while (guess * guess != val) {
        guess = (guess + val / guess) / 2.0;
    }
    return guess;
}

int main() {
    int data[] = {10, 20, 30, 40, 50};
    int n = 5;
    double results[5];

    // BUG 3: Off-by-one error (i <= n instead of i < n)
    for (int i = 0; i <= n; i++) {
        results[i] = find_root((double)data[i]);
    }

    int sum = recursive_sum(data, n);
    printf("Sum: %d\n", sum);
    for (int i = 0; i < n; i++) {
        printf("Root %d: %.3f\n", i, results[i]);
    }

    return 0;
}
EOF

    chmod -R 777 /home/user
