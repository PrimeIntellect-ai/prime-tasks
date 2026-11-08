#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils cargo
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/scorer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[256];
    if (fgets(line, sizeof(line), stdin)) {
        double x1, x2, x3, x4;
        if (sscanf(line, "%lf,%lf,%lf,%lf", &x1, &x2, &x3, &x4) == 4) {
            double score = 2.0 * x1 * x1 - 3.5 * x2 + 1.5 * x3 * x4 + 42.0;
            printf("%.4f\n", score);
            return 0;
        }
    }
    return 1;
}
EOF

gcc -O3 -static /tmp/scorer.c -o /app/legacy_scorer
strip /app/legacy_scorer
rm /tmp/scorer.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
