#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/datagen.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    FILE *f = fopen("/home/user/dataset.csv", "w");
    if (!f) return 1;
    fprintf(f, "y,x1,x2\n");
    for(int i=0; i<100; i++) {
        double x1 = i * 0.1;
        double x2 = (i % 10) * 0.5;
        double noise = (i % 3 == 0) ? 0.1 : -0.1;
        double y = 2.5 - 1.5 * x1 + 3.0 * x2 + noise;
        fprintf(f, "%.4f,%.4f,%.4f\n", y, x1, x2);
    }
    fclose(f);
    return 0;
}
EOF

    chmod -R 777 /home/user
