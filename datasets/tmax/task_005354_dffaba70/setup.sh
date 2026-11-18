#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ curl wget
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/risk_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 4) return 1;
    double price = atof(argv[1]);
    double vol = atof(argv[2]);
    double time = atof(argv[3]);
    double result = price * exp(vol * sqrt(time));
    printf("%.6f\n", result);
    return 0;
}
EOF
    gcc -O3 -s /tmp/risk_calc.c -o /app/risk_calc -lm
    chmod +x /app/risk_calc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
