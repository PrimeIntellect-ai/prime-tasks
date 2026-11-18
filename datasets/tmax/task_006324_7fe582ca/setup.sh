#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > align_fit.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void waste_time() {
    volatile int sum = 0;
    for(int i=0; i<500000000; i++) {
        sum += i;
    }
}

int score_alignment(const char* primer) {
    waste_time();
    return strlen(primer) * 2;
}

int main() {
    const char* primers[] = {"ATGC", "GCTAGCT", "CGTAGCTAGCA", "A", "TG"};
    int n = 5;
    double sum_x = 0, sum_y = 0, sum_xy = 0, sum_xx = 0;

    for(int i=0; i<n; i++) {
        int len = strlen(primers[i]);
        int score = score_alignment(primers[i]);
        sum_x += len;
        sum_y += score;
        sum_xy += len * score;
        sum_xx += len * len;
    }

    double slope = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x * sum_x);
    double intercept = (sum_y - slope * sum_x) / n;

    printf("Slope: %.2f, Intercept: %.2f\n", slope, intercept);
    return 0;
}
EOF

    cat << 'EOF' > expected_result.txt
Slope: 2.00, Intercept: 0.00
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
