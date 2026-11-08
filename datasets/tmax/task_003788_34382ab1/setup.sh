#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest pandas flask fastapi uvicorn requests numpy

    mkdir -p /app
    cat << 'EOF' > /app/sensor_gen.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double rand_float() {
    return (double)rand() / RAND_MAX;
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int N = atoi(argv[1]);
    srand(42);

    printf("id,timestamp,sensor_A,sensor_B,sensor_C,metadata\n");

    int prev_id = 0;
    double sensor_B_val = 0.0;

    for (int i = 1; i <= N; i++) {
        int id = i;
        if (i > 1 && rand_float() < 0.01) {
            id = prev_id;
        } else {
            prev_id = id;
        }

        int timestamp = 1700000000 + i * 10;

        double sensor_A = sin(i / 10.0) * 50.0 + (rand_float() * 2.0 - 1.0);
        sensor_B_val += (rand_float() * 2.0 - 1.0);
        double sensor_B = sensor_B_val;
        double sensor_C = 10.0 + (rand_float() * 1.0);

        if (i == 500) sensor_A = 999.9;
        if (i == 1200) { sensor_B_val += 50.0; sensor_B = sensor_B_val; }
        if (i == 3500) sensor_C = -100.0;

        const char* metadata = "\"Status OK\"";
        if (rand_float() < 0.05) {
            metadata = "\"Warning:\nValue fluctuating\"";
        }

        if (rand_float() < 0.02) {
            printf("%d,%d,%f,,%f,%s\n", id, timestamp, sensor_A, sensor_C, metadata);
        } else {
            printf("%d,%d,%f,%f,%f,%s\n", id, timestamp, sensor_A, sensor_B, sensor_C, metadata);
        }
    }
    return 0;
}
EOF

    gcc -O2 /app/sensor_gen.c -o /app/sensor_gen -lm
    chmod +x /app/sensor_gen
    rm /app/sensor_gen.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
