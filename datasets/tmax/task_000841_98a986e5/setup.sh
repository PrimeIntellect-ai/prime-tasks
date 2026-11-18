#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install --default-timeout=100 pytest flask fastapi uvicorn scikit-learn numpy scipy h5py pandas joblib

    mkdir -p /app
    cat << 'EOF' > /app/extractor.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 4) return 1;
    double x = atof(argv[1]);
    double y = atof(argv[2]);
    double z = atof(argv[3]);
    // Target function
    double res = sin(x) * (y * y) + log(fabs(z) + 1.0);
    printf("%.6f\n", res);
    return 0;
}
EOF

    gcc -O3 /app/extractor.c -o /app/legacy_extractor -lm
    strip /app/legacy_extractor
    chmod +x /app/legacy_extractor
    rm /app/extractor.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
