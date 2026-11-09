#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/wal_struct.h
#ifndef WAL_STRUCT_H
#define WAL_STRUCT_H
#include <stdint.h>

struct WAL_Header {
    char magic[4]; // "WAL1"
    uint32_t num_records;
};

struct WAL_Record {
    uint32_t id;
    double original_val;
    float stored_val;
    char data[32];
};
#endif
EOF

    cat << 'EOF' > /home/user/app.log
[INFO] Container started.
[INFO] Opening WAL file...
[INFO] Found 5 records in WAL.
[INFO] Processing record ID 1
[INFO] Processing record ID 2
[INFO] Processing record ID 3
[INFO] Processing record ID 4
[ERROR] Segmentation fault (core dumped)
EOF

    cat << 'EOF' > /home/user/gen_wal.py
import struct

with open('/home/user/wal.dat', 'wb') as f:
    # Header: "WAL1", 5 records
    f.write(struct.pack('<4sI', b'WAL1', 5))

    # Record 1
    f.write(struct.pack('<Idf32s', 1, 15.5, 15.5, b'data1'))

    # Record 2: Precision loss! 
    # original = 123456789.123, stored = float(123456789.123) which is 123456792.0
    f.write(struct.pack('<Idf32s', 2, 123456789.123, 123456789.123, b'data2'))

    # Record 3
    f.write(struct.pack('<Idf32s', 3, 20.0, 20.0, b'data3'))

    # Record 4: Corrupted record causing crash
    f.write(struct.pack('<Idf32s', 4, 99.9, 99.9, b'CORRUPTED_NO_NULL_TERMINATOR_HERE_BLABLABLABLABLA'))

    # Record 5
    f.write(struct.pack('<Idf32s', 5, 42.0, 42.0, b'data5'))
EOF

    python3 /home/user/gen_wal.py
    rm /home/user/gen_wal.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
