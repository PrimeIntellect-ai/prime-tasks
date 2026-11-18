#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/app/data

    cat << 'EOF' > /tmp/generate_data.py
import os

os.makedirs('/home/user/app/data', exist_ok=True)
total = 0
for i in range(1, 5):
    with open(f'/home/user/app/data/region{i}.txt', 'w') as f:
        for j in range(100000):
            # Deterministic value based on i and j
            val = (i * j) % 50 + 1
            f.write(f"{val}\n")
            total += val * val

with open('/home/user/app/expected_total.txt', 'w') as f:
    f.write(str(total))
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    cat << 'EOF' > /home/user/app/aggregator.c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

unsigned long long total_sum = 0;

void* process_file(void* arg) {
    char* filename = (char*)arg;
    FILE* file = fopen(filename, "r");
    if (!file) return NULL;

    unsigned long long local_sum = 0;
    int val;
    while (fscanf(file, "%d", &val) == 1) {
        local_sum += (unsigned long long)val * val;
    }
    fclose(file);

    // BUG: Race condition here
    total_sum += local_sum;

    return NULL;
}

int main() {
    pthread_t threads[4];
    char* files[] = {
        "/home/user/app/data/region1.txt",
        "/home/user/app/data/region2.txt",
        "/home/user/app/data/region3.txt",
        "/home/user/app/data/region4.txt"
    };

    for (int i = 0; i < 4; i++) {
        pthread_create(&threads[i], NULL, process_file, files[i]);
    }

    for (int i = 0; i < 4; i++) {
        pthread_join(threads[i], NULL);
    }

    printf("%llu\n", total_sum);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
