#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go postgresql postgresql-client gcc
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/legacy_cleaner.c
#include <stdio.h>
#include <math.h>

int main() {
    double x;
    double ema = 0.0;
    int first = 1;
    while (scanf("%lf", &x) == 1) {
        if (first) {
            ema = x;
            first = 0;
        } else {
            ema = 0.3 * x + 0.7 * ema;
        }
        double out = tanh(x - ema);
        printf("%.6f ", out);
    }
    printf("\n");
    return 0;
}
EOF

gcc -O2 -o /app/legacy_cleaner /tmp/legacy_cleaner.c -lm
strip /app/legacy_cleaner
rm /tmp/legacy_cleaner.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
