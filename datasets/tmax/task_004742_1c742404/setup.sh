#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ file binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/dist_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char id1[64], id2[64], id3[64];
    char axis1, axis2, axis3;
    float v1, v2, v3;

    if (scanf("%s %c %f", id1, &axis1, &v1) != 3) return 1;
    if (scanf("%s %c %f", id2, &axis2, &v2) != 3) return 1;
    if (scanf("%s %c %f", id3, &axis3, &v3) != 3) return 1;

    // Proprietary distance logic: Euclidean distance squared from origin
    float dist = (v1*v1) + (v2*v2) + (v3*v3);
    printf("%.2f\n", dist);
    return 0;
}
EOF

    gcc /tmp/dist_calc.c -o /app/dist_calc
    strip /app/dist_calc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
