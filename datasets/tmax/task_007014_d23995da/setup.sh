#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/workspace
    cd /home/user/workspace

    cat << 'EOF' > generate_data.py
import struct
import random

random.seed(42)

def generate():
    with open("data.bin", "wb") as f:
        count = 0
        total_sum = 0.0

        for i in range(2000000):
            # 1% chance of corruption (insert random bytes)
            if random.random() < 0.01:
                f.write(bytes([random.randint(0x00, 0xA9)] * random.randint(1, 5)))

            val = random.uniform(10.0, 100.0)
            f.write(struct.pack('<BHfB', 0xAA, i % 1000, val, 0x00))
            count += 1
            total_sum += val

        print(f"EXPECTED_COUNT={count}")
        print(f"EXPECTED_AVG={total_sum/count:.4f}")

generate()
EOF

    python3 generate_data.py > expected_results.txt

    cat << 'EOF' > sensor_aggregator.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <pthread.h>
#include <sys/stat.h>

#define NUM_THREADS 4

#pragma pack(push, 1)
typedef struct {
    uint8_t magic;
    uint16_t sensor_id;
    float value;
    uint8_t padding;
} Record;
#pragma pack(pop)

float global_sum = 0.0f;
uint32_t global_count = 0;

typedef struct {
    uint8_t *data;
    size_t size;
} ThreadArgs;

void* process_data(void* arg) {
    ThreadArgs* args = (ThreadArgs*)arg;
    size_t offset = 0;

    while (offset + sizeof(Record) <= args->size) {
        if (args->data[offset] != 0xAA) {
            // BUG 1: Aborts on corruption instead of scanning
            printf("Corruption detected. Aborting thread.\n");
            break;
        }

        Record* rec = (Record*)&args->data[offset];

        // BUG 2: Race condition
        // BUG 3: Precision loss (float)
        global_sum += rec->value;
        global_count++;

        offset += sizeof(Record);
    }
    return NULL;
}

int main(int argc, char** argv) {
    if (argc != 2) return 1;

    FILE* f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    size_t file_size = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t* data = malloc(file_size);
    fread(data, 1, file_size, f);
    fclose(f);

    pthread_t threads[NUM_THREADS];
    ThreadArgs args[NUM_THREADS];

    size_t chunk_size = file_size / NUM_THREADS;

    for (int i = 0; i < NUM_THREADS; i++) {
        args[i].data = data + (i * chunk_size);
        args[i].size = (i == NUM_THREADS - 1) ? (file_size - i * chunk_size) : chunk_size;
        pthread_create(&threads[i], NULL, process_data, &args[i]);
    }

    for (int i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }

    // Agent needs to output this properly to metrics.log
    printf("Total Count: %u\n", global_count);
    printf("Average Value: %.4f\n", global_sum / global_count);

    free(data);
    return 0;
}
EOF

    cat << 'EOF' > Makefile
all:
	gcc -O2 -pthread sensor_aggregator.c -o sensor_aggregator
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/workspace
    chmod -R 777 /home/user
