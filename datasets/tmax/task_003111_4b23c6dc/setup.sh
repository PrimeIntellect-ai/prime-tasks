#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo rustc
    pip3 install --default-timeout=100 pytest numpy

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <complex.h>

#define PI 3.14159265358979323846

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char *seq = argv[1];
    int N = strlen(seq);
    if (N > 32) {
        // Intentional crash for sequences > 32
        int *p = NULL;
        *p = 0;
    }
    double complex x[32];
    for(int i=0; i<N; i++) {
        if(seq[i] == 'A') x[i] = 1.0;
        else if(seq[i] == 'C') x[i] = 0.5;
        else if(seq[i] == 'G') x[i] = -0.5;
        else if(seq[i] == 'T') x[i] = -1.0;
        else x[i] = 0.0;
    }

    double complex X[32];
    for(int k=0; k<N; k++) {
        X[k] = 0;
        for(int n=0; n<N; n++) {
            X[k] += x[n] * cexp(-I * 2 * PI * k * n / N);
        }
    }

    double P[32];
    for(int k=0; k<N; k++) {
        P[k] = creal(X[k])*creal(X[k]) + cimag(X[k])*cimag(X[k]);
    }

    double tv = 0;
    for(int k=0; k<N-1; k++) {
        tv += fabs(P[k+1] - P[k]);
    }

    printf("%.6f\n", tv);
    return 0;
}
EOF

    gcc /tmp/oracle.c -o /app/seq_oracle -lm -s
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/analyzer

    python3 -c "import random; f=open('/home/user/sequences.txt', 'w'); [f.write(''.join(random.choices('ACGT', k=100)) + '\n') for _ in range(100)]; f.close()"

    chmod -R 777 /home/user
