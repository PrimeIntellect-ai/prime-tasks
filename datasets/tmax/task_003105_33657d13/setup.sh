#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev make
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/wal.log
0 15.5
1 20.0
2 -5.5
CORRUPT_ENTRY_XYZ 999
0 4.5
1 -10.0
EOF

    cat << 'EOF' > /home/user/pipeline.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main() {
    char* data_dir = getenv("DATA_DIR");
    if (!data_dir) {
        fprintf(stderr, "Fatal: DATA_DIR environment variable not set.\n");
        return 1;
    }

    char filepath[256];
    snprintf(filepath, sizeof(filepath), "%s/wal.log", data_dir);

    FILE* file = fopen(filepath, "r");
    if (!file) {
        fprintf(stderr, "Fatal: Could not open %s\n", filepath);
        return 1;
    }

    float values[3] = {0.0, 0.0, 0.0};
    char line[256];

    while (fgets(line, sizeof(line), file)) {
        int id;
        float val;
        // Bug 1: Fails hard on corrupted WAL entries
        if (sscanf(line, "%d %f", &id, &val) != 2) {
            fprintf(stderr, "WAL Corruption detected! Aborting.\n");
            exit(1);
        }
        if (id >= 0 && id < 3) {
            values[id] += val;
        }
    }
    fclose(file);

    // Iterative smoothing algorithm
    float diff = 100.0;
    int iterations = 0;

    while (diff > 0.001 && iterations < 1000) {
        float old_val = values[0];
        values[0] = (values[0] + values[1] + values[2]) / 3.0;

        // Bug 2: Convergence failure (missing absolute value, can become negative and falsely converge, or oscillate)
        diff = old_val - values[0]; 

        iterations++;
    }

    FILE* out = fopen("/home/user/output.txt", "w");
    if (out) {
        fprintf(out, "Final State: %.3f %.3f %.3f\n", values[0], values[1], values[2]);
        fprintf(out, "Iterations: %d\n", iterations);
        fclose(out);
    }

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
