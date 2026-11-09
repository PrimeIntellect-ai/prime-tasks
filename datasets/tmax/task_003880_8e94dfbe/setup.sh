#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/metrics.dat
10
50
90
85
20
95
100
30
86
40
EOF

    cat << 'EOF' > /home/user/worker.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    FILE *fp = fopen("/home/user/metrics.dat", "r");
    if (!fp) {
        perror("Failed to open metrics.dat");
        return 1;
    }

    // TODO: Replace this hardcoded threshold with the ALERT_THRESHOLD environment variable.
    // Default to 80 if the variable is not set or is invalid.
    int threshold = 50; 

    int val;
    while (fscanf(fp, "%d", &val) == 1) {
        if (val > threshold) {
            printf("CRITICAL: Value %d exceeds threshold\n", val);
        } else {
            printf("INFO: Value %d is normal\n", val);
        }
    }

    fclose(fp);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
