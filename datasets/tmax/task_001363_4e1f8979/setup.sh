#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc libc6-dev
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/ref_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    double seed = atof(argv[1]);
    int n = 1000000;
    double mean = 0.0;
    double M2 = 0.0;
    for (int i = 0; i < n; i++) {
        double x = sin(i * seed) * 1e5 + 1e8;
        double delta = x - mean;
        mean += delta / (i + 1);
        M2 += delta * (x - mean);
    }
    double variance = M2 / n;
    printf("%.10f\n", variance);
    return 0;
}
EOF
    gcc -O3 -o /app/ref_calc /app/ref_calc.c -lm
    strip /app/ref_calc

    mkdir -p /home/user/timeseries_proj
    cd /home/user/timeseries_proj
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > calc_var.py
import sys
import math

def main():
    seed = float(sys.argv[1])
    n = 1000000
    mean = 0.0
    M2 = 0.0
    for i in range(n):
        x = math.sin(i * seed) * 1e5 + 1e8
        delta = x - mean
        mean += delta / (i + 1)
        M2 += delta * (x - mean)
    print(M2 / n)

if __name__ == '__main__':
    main()
EOF

    git add calc_var.py
    git commit -m "Initial commit with Welford algorithm"

    for i in $(seq 2 149); do
        echo "# dummy $i" >> calc_var.py
        git commit -am "Commit $i"
    done

    cat << 'EOF' > calc_var.py
import sys
import math

def main():
    seed = float(sys.argv[1])
    n = 1000000
    sum_x = 0.0
    sum_sq = 0.0
    for i in range(n):
        x = math.sin(i * seed) * 1e5 + 1e8
        sum_x += x
        sum_sq += x * x
    print(sum_sq / n - (sum_x / n)**2)

if __name__ == '__main__':
    main()
EOF

    git commit -am "Optimize variance calculation"

    for i in $(seq 151 200); do
        echo "# optimization $i" >> calc_var.py
        git commit -am "Commit $i"
    done

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
