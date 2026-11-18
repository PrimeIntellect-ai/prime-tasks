#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/project/src
    mkdir -p /home/user/project/lib
    mkdir -p /home/user/project/scripts
    mkdir -p /home/user/project/data

    cat << 'EOF' > /home/user/project/src/processor.c
#include <stdint.h>
#include <stdio.h>
#include <string.h>

struct Record {
    int32_t id;
    float value;
    char name[16];
};

void process_record(struct Record* rec, char* out_buf) {
    sprintf(out_buf, "ID:%d|VAL:%.2f|NAME:%s", rec->id, rec->value, rec->name);
}
EOF

    cat << 'EOF' > /home/user/project/src/Makefile
all:
	gcc -O2 processor.c -o ../lib/libprocessor.so
EOF

    cat << 'EOF' > /home/user/project/scripts/process.py
import ctypes
import os
import glob
import zlib
import struct

# TODO: Define Record structure here

lib = ctypes.CDLL('../lib/libprocessor.so')
# TODO: Set argtypes and restype for lib.process_record

def main():
    data_dir = '../data'
    # TODO: Iterate over .dat files, check CRC32, unpack data, call C function, and append to ../output.log

if __name__ == "__main__":
    main()
EOF

    python3 -c "
import struct
import zlib
import os

def create_record(filename, id_val, float_val, name_val, valid=True):
    payload = struct.pack('<if16s', id_val, float_val, name_val.encode('utf-8'))
    checksum = zlib.crc32(payload) & 0xffffffff
    if not valid:
        checksum = (checksum + 1) & 0xffffffff
    with open(filename, 'wb') as f:
        f.write(struct.pack('<I', checksum))
        f.write(payload)

create_record('/home/user/project/data/record_1.dat', 1, 3.14, 'alpha', True)
create_record('/home/user/project/data/record_2.dat', 2, 2.71, 'beta', True)
create_record('/home/user/project/data/record_3.dat', 3, 1.41, 'gamma', False)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
