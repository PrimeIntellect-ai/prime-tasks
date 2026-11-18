#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest numpy matplotlib scipy pandas scikit-learn

    # Create the C source file
    cat << 'EOF' > /tmp/sim.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <workload_id>\n", argv[0]);
        return 1;
    }
    int workload_id = atoi(argv[1]);
    srand(workload_id * 1337);

    printf("INFO: Initializing hardware simulation for workload %d...\n", workload_id);
    printf("DEBUG: Mapping memory pages...\n");
    printf("--- BEGIN DATA ---\n");

    for (int i = 0; i < 100; i++) {
        float c0 = (float)(rand() % 1000) / 10.0f;
        float c1 = (float)(rand() % 1000) / 10.0f;
        float c2 = (float)(rand() % 1000) / 10.0f;

        float v[10];
        v[0] = c0;
        v[1] = c1;
        v[2] = c2;
        v[3] = c0 * 1.5f + c1 * 0.5f + ((float)(rand()%10)/10.0f);
        v[4] = c2 * 2.0f - c0 * 0.2f + ((float)(rand()%10)/10.0f);
        v[5] = c1 * 0.8f + c2 * 1.1f + ((float)(rand()%10)/10.0f);
        v[6] = c0 + c1 + c2;
        v[7] = c0 * 0.1f + c1 * 0.2f + c2 * 0.3f;
        v[8] = v[3] + v[4];
        v[9] = v[5] - v[6] + ((float)(rand()%10)/10.0f);

        for (int j = 0; j < 10; j++) {
            printf("%.4f%s", v[j], (j == 9) ? "" : " ");
        }
        printf("\n");
    }

    printf("--- END DATA ---\n");
    printf("INFO: Simulation complete.\n");
    printf("DEBUG: Unmapping memory.\n");
    return 0;
}
EOF

    # Compile and strip the binary
    mkdir -p /app
    gcc -O2 /tmp/sim.c -o /app/hardware_sim -lm
    strip /app/hardware_sim
    rm /tmp/sim.c

    # Create the user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
