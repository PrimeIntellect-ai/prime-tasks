#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/consensus_debugger
    cd /home/user/consensus_debugger

    cat << 'EOF' > traffic.log
10.5
11.0
10.8
11.2
10.9
11.1
11.0
11.05
11.02
11.0
EOF

    cat << 'EOF' > sim.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main() {
    // 1. Environment check
    char* env_mode = getenv("AGGREGATOR_MODE");
    if (env_mode == NULL || strcmp(env_mode, "DEBUG") != 0) {
        fprintf(stderr, "FATAL: AGGREGATOR_MODE environment variable must be set to 'DEBUG'\n");
        return 1;
    }

    FILE *file = fopen("traffic.log", "r");
    if (!file) {
        perror("Failed to open traffic.log");
        return 1;
    }

    double current_estimate = 10.0;
    // BUG: alpha > 1 causes oscillation in EMA. Should be something like 0.2
    // The previous dev accidentally wrote 1.2 instead of 0.2
    double alpha = 1.2; 

    char line[256];
    while (fgets(line, sizeof(line), file)) {
        double sensor_val = atof(line);

        // Convergence logic
        current_estimate = current_estimate + alpha * (sensor_val - current_estimate);

        // Use a math library function to force the linker error requirement
        current_estimate = round(current_estimate * 10000.0) / 10000.0;
    }

    fclose(file);
    printf("Final estimate: %.4f\n", current_estimate);
    return 0;
}
EOF

    cat << 'EOF' > Makefile
sim: sim.c
	gcc -o sim sim.c
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
