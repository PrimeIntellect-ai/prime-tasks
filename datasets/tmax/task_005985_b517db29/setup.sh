#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip protobuf-c-compiler libprotobuf-c-dev protobuf-compiler python3-protobuf gcc make libc6-dev valgrind
    pip3 install pytest

    mkdir -p /home/user/analytics_service

    cat << 'EOF' > /home/user/analytics_service/Makefile
CC = gcc
CFLAGS = -Wall -g

all: analytics_engine

analytics_engine: compute.o
	$(CC) $(CFLAGS) -o analytics_engine compute.o # BUG: Missing libraries and generated protobuf files

compute.o: compute.c
	$(CC) $(CFLAGS) -c compute.c

clean:
	rm -f *.o analytics_engine *.pb-c.c *.pb-c.h *_pb2.py
EOF

    cat << 'EOF' > /home/user/analytics_service/compute.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "schema.pb-c.h"

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;

    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t *buf = malloc(len);
    fread(buf, 1, len, f);
    fclose(f);

    DataBatch *batch = data_batch__unpack(NULL, len, buf);
    free(buf); // free buffer

    if (!batch) return 1;

    double mean = 0.0;
    double M2 = 0.0;

    // BUG: Off-by-one error causing out-of-bounds read
    for (size_t i = 0; i <= batch->n_samples; i++) {
        double delta = batch->samples[i] - mean;
        mean += delta / (i + 1);
        double delta2 = batch->samples[i] - mean;
        M2 += delta * delta2;
    }

    // BUG: Division by zero if n_samples < 2
    double variance = M2 / (batch->n_samples - 1);

    printf("Mean: %.6f\n", mean);
    printf("Variance: %.6f\n", variance);

    // BUG: Missing data_batch__free_unpacked(batch, NULL); causing memory leak

    return 0;
}
EOF

    cat << 'EOF' > /home/user/analytics_service/generate_test_data.py
import sys
try:
    import schema_pb2
except ImportError:
    print("schema_pb2 not found. Please compile schema.proto to python first.")
    sys.exit(1)

batch = schema_pb2.DataBatch()
samples = [10.5, 12.0, 15.5, 14.0, 18.5, 13.5]
batch.samples.extend(samples)

with open("test_batch.bin", "wb") as f:
    f.write(batch.SerializeToString())
EOF

    chmod +x /home/user/analytics_service/generate_test_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/analytics_service
    chmod -R 777 /home/user
