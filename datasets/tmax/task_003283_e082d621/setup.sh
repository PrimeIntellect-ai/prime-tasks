#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev rustc cargo
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/bench.c
#include <stdio.h>
#include <time.h>

extern void init_metrics(size_t capacity);
extern double record_and_average(double latency);

int main() {
    init_metrics(3);

    double inputs[] = {10.0, 20.0, 30.0, 40.0, 50.0};

    clock_t start = clock();
    for(int i = 0; i < 5; i++) {
        double avg = record_and_average(inputs[i]);
        printf("Avg after %.1f: %.1f\n", inputs[i], avg);
    }
    clock_t end = clock();

    printf("Execution completed.\n");
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
