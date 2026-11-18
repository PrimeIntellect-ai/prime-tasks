#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    # Create app directory
    mkdir -p /app

    # Create the legacy C++ scanner
    cat << 'EOF' > /tmp/legacy_scanner.cpp
#include <iostream>
#include <fstream>
#include <map>
#include <vector>
#include <cstdint>

struct Agg {
    uint64_t count = 0;
    uint64_t total_payload = 0;
};

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* f = fopen(argv[1], "rb");
    if (!f) return 1;

    std::map<uint32_t, Agg> aggs;
    while (true) {
        uint8_t magic;
        if (fread(&magic, 1, 1, f) != 1) break;
        if (magic != 0xAB) break;

        uint64_t timestamp = 0;
        for(int i=0; i<8; ++i) {
            uint8_t b; if (fread(&b, 1, 1, f) != 1) break;
            timestamp |= (uint64_t)b << (i*8);
        }
        uint32_t txid = 0;
        for(int i=0; i<4; ++i) {
            uint8_t b; if (fread(&b, 1, 1, f) != 1) break;
            txid |= (uint32_t)b << (i*8);
        }
        uint16_t payload_len = 0;
        for(int i=0; i<2; ++i) {
            uint8_t b; if (fread(&b, 1, 1, f) != 1) break;
            payload_len |= (uint16_t)b << (i*8);
        }

        for(int i=0; i<payload_len; ++i) {
            uint8_t b; if (fread(&b, 1, 1, f) != 1) break;
        }

        aggs[txid].count++;
        aggs[txid].total_payload += payload_len;
    }
    fclose(f);

    std::cout << "TxID,RecordCount,TotalPayloadBytes\n";
    for (const auto& pair : aggs) {
        std::cout << pair.first << "," << pair.second.count << "," << pair.second.total_payload << "\n";
    }
    return 0;
}
EOF

    # Compile and strip the legacy scanner
    g++ -O0 /tmp/legacy_scanner.cpp -o /app/wal_scanner
    strip -s /app/wal_scanner
    rm /tmp/legacy_scanner.cpp

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate sample WAL file
    cat << 'EOF' > /tmp/gen_wal.py
import struct
import random

def generate_wal(path, size_bytes):
    with open(path, 'wb') as f:
        written = 0
        while written < size_bytes:
            magic = 0xAB
            timestamp = random.randint(1000000000, 2000000000)
            txid = random.randint(1, 100)
            payload_len = random.randint(10, 100)
            payload = bytes([random.randint(0, 255) for _ in range(payload_len)])

            record = struct.pack('<BQIH', magic, timestamp, txid, payload_len) + payload
            f.write(record)
            written += len(record)

generate_wal('/home/user/sample.wal', 10 * 1024 * 1024)
EOF

    python3 /tmp/gen_wal.py
    rm /tmp/gen_wal.py

    chmod -R 777 /home/user
