#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/sim.c
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

int main() {
    srand(time(NULL));
    int id = 0;
    while(1) {
        float v1, v2, v3;
        int is_anomaly = (rand() % 100) < 5;
        if (is_anomaly) {
            v1 = 8.0 + (float)rand()/(float)(RAND_MAX/5.0);
            v2 = 8.0 + (float)rand()/(float)(RAND_MAX/5.0);
            v3 = (float)rand()/(float)(RAND_MAX/1.9);
        } else {
            v1 = (float)rand()/(float)(RAND_MAX/10.0);
            v2 = (float)rand()/(float)(RAND_MAX/10.0);
            v3 = 2.0 + (float)rand()/(float)(RAND_MAX/8.0);
        }
        printf("{\"sensor_id\": %d, \"v1\": %.2f, \"v2\": %.2f, \"v3\": %.2f}\n", id++, v1, v2, v3);
        fflush(stdout);
        usleep(10000); // 10ms
    }
    return 0;
}
EOF

gcc -O2 /tmp/sim.c -o /app/sensor_simulator
strip /app/sensor_simulator
rm /tmp/sim.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
