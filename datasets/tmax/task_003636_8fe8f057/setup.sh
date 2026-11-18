#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_calc.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    double x;
    long n = 0;
    double mean = 0.0;
    double M2 = 0.0;

    while (scanf("%lf", &x) == 1) {
        n++;
        double delta = x - mean;
        mean += delta / n;
        double delta2 = x - mean;
        M2 += delta * delta2;
    }

    if (n < 2) {
        printf("Mean: 0.000000\nVariance: 0.000000\n");
    } else {
        printf("Mean: %.6f\nVariance: %.6f\n", mean, M2 / (n - 1));
    }

    return 0;
}
EOF
    gcc -o /app/legacy_calc /app/legacy_calc.c
    strip /app/legacy_calc
    rm /app/legacy_calc.c

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/calc_metrics.py
import sys

def process_metrics():
    data = []
    for line in sys.stdin:
        line = line.strip()
        if line:
            data.append(float(line))

    if len(data) < 2:
        print("Mean: 0.000000")
        print("Variance: 0.000000")
        return

    n = len(data)
    mean = sum(data) / n

    # Naive variance calculation
    sum_sq = sum(x**2 for x in data)
    variance = (sum_sq - n * (mean**2)) / (n - 1)

    print(f"Mean: {mean:.6f}")
    print(f"Variance: {variance:.6f}")

if __name__ == "__main__":
    process_metrics()
EOF

    chmod -R 777 /home/user
