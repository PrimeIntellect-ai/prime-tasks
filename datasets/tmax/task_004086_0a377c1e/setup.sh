#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk bc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <string.h>
#include <math.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    char *seq = argv[1];
    int len = strlen(seq);
    int gc = 0;
    for (int i=0; i<len; i++) {
        if (seq[i] == 'G' || seq[i] == 'C') gc++;
    }
    double P = (double)gc / len;
    double T = 0.5;
    for(int i=0; i<10; i++) {
        double f = T * exp(T) - P;
        double df = exp(T) * (T + 1.0);
        T = T - (f / df);
    }
    double S = T * len;
    printf("%.6f\n", S);
    return 0;
}
EOF
    gcc -O2 -s /tmp/oracle.c -lm -o /app/primer_oracle
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
