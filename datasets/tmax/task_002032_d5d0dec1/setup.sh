#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    # Create the reference data
    mkdir -p /home/user
    cat << 'EOF' > /home/user/reference_data.csv
1.0,2.0,3.0,4.0,5.0
2.0,3.0,4.0,5.0,6.0
3.0,4.0,5.0,6.0,7.0
4.0,5.0,6.0,7.0,8.0
EOF

    # Create the binary
    mkdir -p /app
    cat << 'EOF' > /tmp/analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    char *engine = getenv("MATRIX_ENGINE");
    if (engine == NULL || strcmp(engine, "blas") != 0) {
        return 0; // Simulate the "blank output" issue
    }

    char line[256];
    if (fgets(line, sizeof(line), stdin) == NULL) return 1;

    float v[5];
    if (sscanf(line, "%f,%f,%f,%f,%f", &v[0], &v[1], &v[2], &v[3], &v[4]) != 5) return 1;

    // Dummy linear algebra projection (sum of squares scaled by 0.5)
    float score = 0.0;
    for(int i=0; i<5; i++) {
        score += (v[i] * 0.5) * (v[i] * 0.5);
    }

    printf("%.2f\n", sqrt(score));
    return 0;
}
EOF
    gcc -O2 /tmp/analyzer.c -o /app/analyzer -lm
    strip /app/analyzer
    rm /tmp/analyzer.c
    chmod +x /app/analyzer

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
