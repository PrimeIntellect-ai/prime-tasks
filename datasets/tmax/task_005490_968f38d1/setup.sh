#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_service.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

typedef struct {
    char name[16];
    double value;
} SensorData;

float total_sum = 0.0;

void process_data(const char* input_name, double val) {
    SensorData* data = malloc(sizeof(SensorData));
    // Buffer overflow here
    strcpy(data->name, input_name);
    data->value = val;

    // Race condition and precision issue here
    total_sum += data->value;

    // Memory leak: data is never freed
}

void* worker(void* arg) {
    char* name = (char*)arg;
    for(int i=0; i<1000000; i++) {
        process_data(name, 0.000001);
    }
    return NULL;
}

int main() {
    pthread_t t1, t2;
    pthread_create(&t1, NULL, worker, "sensorA");
    pthread_create(&t2, NULL, worker, "sensorB");

    pthread_join(t1, NULL);
    pthread_join(t2, NULL);

    printf("%.6f\n", total_sum);
    return 0;
}
EOF

    python3 -c '
import os
with open("/home/user/crash_dump.bin", "wb") as f:
    f.write(os.urandom(1024))
    f.write(b"SENSOR_OVERFLOW_TRIGGER_99281\x00")
    f.write(os.urandom(2048))
'

    chmod -R 777 /home/user
