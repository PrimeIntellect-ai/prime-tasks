#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/src

    cat << 'EOF' > /app/true_relax.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_N 500

int main() {
    char header[1024];
    if (!fgets(header, sizeof(header), stdin)) return 0;

    int vals[MAX_N];
    int n = 0;
    while (scanf("%d", &vals[n]) == 1) {
        n++;
    }

    for (int iter = 0; iter < 5; iter++) {
        int grad[MAX_N];
        int max_g = 0;
        for (int i = 0; i < n; i++) {
            grad[i] = vals[i];
            for (int j = 0; j < n; j++) {
                if (i == j) continue;
                int diff = vals[i] - vals[j];
                int abs_diff = diff > 0 ? diff : -diff;
                if (abs_diff < 10) {
                    grad[i] += (diff > 0 ? 1 : -1) * (10 - abs_diff);
                }
            }
            int abs_g = grad[i] > 0 ? grad[i] : -grad[i];
            if (abs_g > max_g) max_g = abs_g;
        }
        int dt_divisor = 1 + (max_g / 10);
        for (int i = 0; i < n; i++) {
            vals[i] -= grad[i] / dt_divisor;
        }
    }

    for (int i = 0; i < n; i++) {
        printf("%d ", vals[i]);
    }
    printf("\n");
    return 0;
}
EOF

    gcc -O2 /app/true_relax.c -o /app/relax_bin
    strip /app/relax_bin
    rm /app/true_relax.c

    cat << 'EOF' > /home/user/src/relax.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_N 500

int main() {
    char header[1024];
    if (!fgets(header, sizeof(header), stdin)) return 0;

    int vals[MAX_N];
    int n = 0;
    while (scanf("%d", &vals[n]) == 1) {
        n++;
    }

    for (int iter = 0; iter < 5; iter++) {
        int grad[MAX_N];
        for (int i = 0; i < n; i++) {
            grad[i] = vals[i];
            for (int j = 0; j < n; j++) {
                if (i == j) continue;
                int diff = vals[i] - vals[j];
                int abs_diff = diff > 0 ? diff : -diff;
                if (abs_diff < 10) {
                    grad[i] += (diff > 0 ? 1 : -1) * (10 - abs_diff);
                }
            }
        }
        int dt_divisor = 1; // Missing adaptive step size logic
        for (int i = 0; i < n; i++) {
            vals[i] -= grad[i] / dt_divisor;
        }
    }

    for (int i = 0; i < n; i++) {
        printf("%d ", vals[i]);
    }
    printf("\n");
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod 755 /app/relax_bin
