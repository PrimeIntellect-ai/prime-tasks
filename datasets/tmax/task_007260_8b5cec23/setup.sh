#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/cleaner.h
#ifndef CLEANER_H
#define CLEANER_H

void clean_batch_isolated(float* data, int size);
void clean_batch_leaky(float* data, int size);

#endif
EOF

    cat << 'EOF' > /home/user/cleaner.c
#include "cleaner.h"

static double global_sum = 0;
static int global_count = 0;

void clean_batch_isolated(float* data, int size) {
    double sum = 0;
    for(int i = 0; i < size; i++) {
        sum += data[i];
    }
    float mean = (float)(sum / size);
    for(int i = 0; i < size; i++) {
        data[i] -= mean;
    }
}

void clean_batch_leaky(float* data, int size) {
    for(int i = 0; i < size; i++) {
        global_sum += data[i];
        global_count++;
    }
    float mean = (float)(global_sum / global_count);
    for(int i = 0; i < size; i++) {
        data[i] -= mean;
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
