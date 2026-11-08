#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /app

    # Generate profiles.csv
    cat << 'EOF' > /tmp/generate_data.py
import random
random.seed(42)
with open('/home/user/profiles.csv', 'w') as f:
    for _ in range(1000):
        row = []
        for _ in range(20):
            if random.random() < 0.1:
                row.append('')
            else:
                row.append(f"{random.uniform(-1, 1):.4f}")
        f.write(','.join(row) + '\n')
EOF
    python3 /tmp/generate_data.py

    # Create user_embedder.c
    cat << 'EOF' > /tmp/user_embedder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    float matrix[20][5];
    srand(42);
    for (int i = 0; i < 20; i++) {
        for (int j = 0; j < 5; j++) {
            matrix[i][j] = (float)rand() / RAND_MAX * 2.0 - 1.0;
        }
    }

    char line[4096];
    while (fgets(line, sizeof(line), stdin)) {
        float features[20] = {0};
        int count = 0;
        char *token = strtok(line, " \t\n");
        while (token && count < 20) {
            features[count++] = atof(token);
            token = strtok(NULL, " \t\n");
        }

        float out[5] = {0};
        for (int i = 0; i < 20; i++) {
            for (int j = 0; j < 5; j++) {
                out[j] += features[i] * matrix[i][j];
            }
        }
        printf("%.6f %.6f %.6f %.6f %.6f\n", out[0], out[1], out[2], out[3], out[4]);
    }
    return 0;
}
EOF

    gcc -O3 /tmp/user_embedder.c -o /app/user_embedder
    strip /app/user_embedder

    chmod -R 777 /home/user
    chmod -R 755 /app
