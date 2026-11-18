#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/biomodel.c
#include <stdio.h>
#include <string.h>

int count_occurrences(const char *target, const char *primer) {
    int count = 0;
    int target_len = strlen(target);
    int primer_len = strlen(primer);
    for (int i = 0; i <= target_len - primer_len; i++) {
        if (strncmp(&target[i], primer, primer_len) == 0) {
            count++;
        }
    }
    return count;
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <target> <primer>\n", argv[0]);
        return 1;
    }

    int occurrences = count_occurrences(argv[1], argv[2]);
    double k = occurrences * 2.0; // Stiffness

    double x = 1.0;
    double y = 0.0;

    // BUG: dt is too large, causing divergence
    double dt = 0.5;
    double T = 10.0;
    int steps = (int)(T / dt);

    for (int i = 0; i < steps; i++) {
        double dx = y;
        double dy = -k * x - 0.5 * y;
        x += dx * dt;
        y += dy * dt;
    }

    printf("%.4f\n", x);
    return 0;
}
EOF

    chmod -R 777 /home/user
