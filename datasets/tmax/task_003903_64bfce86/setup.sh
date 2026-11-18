#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev valgrind
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/processor.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <stdint.h>

#pragma pack(push, 1)
struct Record {
    uint16_t id;
    double value;
};
#pragma pack(pop)

void process_file(const char* filename) {
    FILE* f = fopen(filename, "rb");
    if (!f) return;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    int num_records = size / sizeof(struct Record);
    struct Record* records = (struct Record*)malloc(size);
    if (fread(records, sizeof(struct Record), num_records, f) != num_records) {
        free(records);
        fclose(f);
        return;
    }
    fclose(f);

    for (int i = 0; i < num_records; i++) {
        uint16_t id = records[i].id; // Bug 1: Missing endianness conversion
        double v = records[i].value;

        // Bug 2: Fails to converge for negative values
        double x = 1.0;
        int iter = 0;
        int converged = 0;
        while (iter < 1000) {
            double fx = x * x - v;
            double dfx = 2 * x;
            double next_x = x - fx / dfx;
            if (fabs(next_x - x) < 1e-6) {
                converged = 1;
                break;
            }
            x = next_x;
            iter++;
        }

        if (!converged) {
            printf("Failed to converge for ID %u\n", id);
            // Bug 3: Memory leak on early return
            return;
        }

        printf("ID %u: %f\n", id, x);
    }

    free(records);
}

int main() {
    process_file("data.bin");
    return 0;
}
EOF

    python3 -c '
import struct
with open("/home/user/data.bin", "wb") as f:
    f.write(struct.pack(">H", 1))
    f.write(struct.pack("<d", 9.0))

    f.write(struct.pack(">H", 2))
    f.write(struct.pack("<d", -4.0)) # Triggers instability & memory leak

    f.write(struct.pack(">H", 3))
    f.write(struct.pack("<d", 16.0))

    f.write(struct.pack(">H", 4))
    f.write(struct.pack("<d", 25.0))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
