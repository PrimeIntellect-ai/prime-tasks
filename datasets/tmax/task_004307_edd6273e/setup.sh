#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;

    double x[10000], y[10000];
    int nx = 0, ny = 0;

    char *arg1 = strdup(argv[1]);
    char *arg2 = strdup(argv[2]);

    char *token = strtok(arg1, " ");
    while (token != NULL) {
        x[nx++] = atof(token);
        token = strtok(NULL, " ");
    }

    token = strtok(arg2, " ");
    while (token != NULL) {
        y[ny++] = atof(token);
        token = strtok(NULL, " ");
    }

    if (nx != ny || nx < 2) return 1;

    double sum_x = 0, sum_y = 0;
    for (int i=0; i<nx; i++) {
        sum_x += x[i];
        sum_y += y[i];
    }
    double mean_x = sum_x / nx;
    double mean_y = sum_y / ny;

    double num = 0, den_x = 0, den_y = 0;
    for (int i=0; i<nx; i++) {
        num += (x[i] - mean_x) * (y[i] - mean_y);
        den_x += (x[i] - mean_x) * (x[i] - mean_x);
        den_y += (y[i] - mean_y) * (y[i] - mean_y);
    }

    double den = sqrt(den_x * den_y);
    if (den == 0.0) {
        printf("0.0000\n");
    } else {
        printf("%.4f\n", num / den);
    }

    free(arg1);
    free(arg2);
    return 0;
}
EOF

    gcc -O2 /app/oracle.c -o /app/metric_oracle -lm
    strip /app/metric_oracle
    rm /app/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
