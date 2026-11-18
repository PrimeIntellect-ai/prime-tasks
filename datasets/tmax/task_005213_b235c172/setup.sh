#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/incoming
    mkdir -p /home/user/samples
    mkdir -p /home/user/dataset_backup/archive
    mkdir -p /home/user/dataset_backup/incremental

    cat << 'EOF' > /app/legacy_parser.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <cstdint>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* f = fopen(argv[1], "rb");
    if (!f) return 1;

    char magic[4];
    for(int i=0; i<4; i++) magic[i] = fgetc(f);
    if (magic[0] != 'W' || magic[1] != 'A' || magic[2] != 'L' || magic[3] != '1') return 1;

    std::string json = "[";
    bool first = true;

    while (true) {
        uint32_t rec_magic = 0;
        int c = fgetc(f); if (c == EOF) break; rec_magic |= (c & 0xFF);
        c = fgetc(f); if (c == EOF) break; rec_magic |= (c & 0xFF) << 8;
        c = fgetc(f); if (c == EOF) break; rec_magic |= (c & 0xFF) << 16;
        c = fgetc(f); if (c == EOF) break; rec_magic |= (c & 0xFF) << 24;

        if (rec_magic != 0xDEADBEEF) break;

        uint64_t ts = 0;
        for(int i=0; i<8; i++) {
            c = fgetc(f); if (c == EOF) break;
            ts |= (uint64_t)(c & 0xFF) << (i * 8);
        }

        uint32_t len = 0;
        for(int i=0; i<4; i++) {
            c = fgetc(f); if (c == EOF) break;
            len |= (c & 0xFF) << (i * 8);
        }

        std::string payload = "";
        for(uint32_t i=0; i<len; i++) {
            c = fgetc(f); if (c == EOF) break;
            payload += (char)c;
        }

        if (!first) {
            json = json + ", ";
        }
        first = false;

        json = json + "{\"ts\": " + std::to_string(ts) + ", \"data\": \"" + payload + "\"}";
    }
    json = json + "]";
    std::cout << json << std::endl;
    fclose(f);
    return 0;
}
EOF

    g++ -O0 /app/legacy_parser.cpp -o /app/legacy_parser
    strip /app/legacy_parser
    rm /app/legacy_parser.cpp

    cat << 'EOF' > /app/gen_wal.py
import struct
import sys

def gen(filename, num_records):
    with open(filename, 'wb') as f:
        f.write(b'WAL1')
        for i in range(num_records):
            f.write(struct.pack('<I', 0xDEADBEEF))
            f.write(struct.pack('<Q', 1600000000000 + i))
            payload = f"sensor_reading_{i}".encode('ascii')
            f.write(struct.pack('<I', len(payload)))
            f.write(payload)

if __name__ == '__main__':
    gen(sys.argv[1], int(sys.argv[2]))
EOF

    python3 /app/gen_wal.py /home/user/samples/sample1.wal 15
    python3 /app/gen_wal.py /home/user/samples/sample2.wal 20
    python3 /app/gen_wal.py /app/hidden_test_500MB.wal 100000

    cat << 'EOF' > /app/verify_speed.py
#!/usr/bin/env python3
import sys
print("Speed verification script placeholder")
EOF
    chmod +x /app/verify_speed.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
