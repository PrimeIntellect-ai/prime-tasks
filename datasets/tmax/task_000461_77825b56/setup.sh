#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev netcat-openbsd socat
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/items.csv
101,1.0,2.0,3.0
102,1.1,2.1,3.1
103,5.0,5.0,5.0
104,1.2,1.9,3.0
105,9.0,9.0,9.0
EOF

    mkdir -p /app
    cat << 'EOF' > /tmp/score_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    char *v1 = argv[1];
    char *v2 = argv[2];

    float f1[100], f2[100];
    int n1 = 0, n2 = 0;

    char *token = strtok(v1, ",");
    while (token) { f1[n1++] = atof(token); token = strtok(NULL, ","); }

    token = strtok(v2, ",");
    while (token) { f2[n2++] = atof(token); token = strtok(NULL, ","); }

    float dist = 0;
    for (int i = 0; i < n1 && i < n2; i++) {
        dist += (f1[i] - f2[i]) * (f1[i] - f2[i]);
    }
    dist = sqrt(dist);
    printf("%f\n", 1.0 / (1.0 + dist));
    return 0;
}
EOF

    gcc -O2 /tmp/score_calc.c -o /app/score_calc -lm
    strip /app/score_calc
    rm /tmp/score_calc.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
