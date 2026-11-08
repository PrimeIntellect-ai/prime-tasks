#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gcc
    pip3 install pytest numpy scipy

    mkdir -p /app
    cat << 'EOF' > /app/eval_source.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    for (int i = 1; i < argc; i++) {
        double x = atof(argv[i]);
        double f = -10000.0 * exp(-10000.0 * (x - 0.5) * (x - 0.5));
        printf("%.10f ", f);
    }
    printf("\n");
    return 0;
}
EOF

    gcc -O2 -s /app/eval_source.c -o /app/eval_source -lm
    rm /app/eval_source.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
