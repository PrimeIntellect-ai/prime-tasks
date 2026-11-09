#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/sensor_logger.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

#pragma pack(push, 1)
typedef struct {
    uint32_t timestamp;
    uint16_t sensor_id;
    int32_t value;
} Record;
#pragma pack(pop)

void log_record(FILE *f, uint32_t ts, uint16_t id, int32_t val) {
    Record *r = malloc(sizeof(Record));
    r->timestamp = ts;
    r->sensor_id = id;
    if (val < 0) {
        free(r); // BUG: Use after free
    }
    r->value = val;
    fwrite(r, sizeof(Record), 1, f);
    fflush(f);
    if (val >= 0) {
        free(r);
    }
}

int main(int argc, char **argv) {
    if (argc != 4) {
        printf("Usage: %s <timestamp> <sensor_id> <value>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen("/home/user/data/sensor.db", "ab");
    if (!f) return 1;
    log_record(f, (uint32_t)atol(argv[1]), (uint16_t)atoi(argv[2]), (int32_t)atoi(argv[3]));
    fclose(f);
    return 0;
}
EOF

    gcc -g -o /home/user/sensor_logger /home/user/sensor_logger.c

    python3 -c "
import struct
with open('/home/user/data/sensor.db', 'wb') as f:
    f.write(struct.pack('<I h i', 1600000000, 1, 25))
    f.write(struct.pack('<I h i', 1600000005, 2, 42))
    f.write(struct.pack('<I h i', 1600000010, 1, 18))
    # Partial record (crash)
    f.write(struct.pack('<I', 1600000015))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
