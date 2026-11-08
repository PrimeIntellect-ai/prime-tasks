#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /app/telemetry_processor.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <stdexcept>
#include <cstring>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::ifstream file(argv[1], std::ios::binary | std::ios::ate);
    if (!file) return 1;
    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);
    std::vector<char> buffer(size);
    if (!file.read(buffer.data(), size)) return 1;

    if (size < 8) return 2;
    if (std::memcmp(buffer.data(), "TLVM", 4) != 0) return 2;

    uint32_t checksum;
    std::memcpy(&checksum, buffer.data() + 4, 4);

    uint32_t calc_checksum = 0;
    for (std::streamsize i = 8; i < size; ++i) {
        calc_checksum += static_cast<unsigned char>(buffer[i]);
    }
    calc_checksum *= 31;

    if (checksum != calc_checksum) return 2;

    size_t pos = 8;
    while (pos < size) {
        if (pos + 3 > size) return 0;
        unsigned char type = buffer[pos];
        uint16_t length;
        std::memcpy(&length, buffer.data() + pos + 1, 2);

        if (type == 0xFF) {
            throw std::runtime_error("Unknown type");
        }

        if (length == 0) {
            while(true) {} // Infinite loop
        }

        if (pos + 3 + length > size) {
            char* p = nullptr;
            *p = 1; // Force segfault
        }

        char* dest = new char[length];
        std::memcpy(dest, buffer.data() + pos + 3, length);
        delete[] dest;

        pos += 3 + length;
    }
    return 0;
}
EOF

    g++ -O2 /app/telemetry_processor.cpp -o /app/telemetry_processor
    strip /app/telemetry_processor
    rm /app/telemetry_processor.cpp

    cat << 'EOF' > /app/generate_corpus.py
import os
import struct

def make_file(path, records, bad_magic=False, bad_checksum=False):
    payload = b''
    for t, v in records:
        payload += struct.pack('<BH', t, len(v)) + v

    magic = b'TLVM' if not bad_magic else b'BADM'

    calc_checksum = (sum(payload) * 31) & 0xFFFFFFFF
    if bad_checksum:
        calc_checksum = (calc_checksum + 1) & 0xFFFFFFFF

    with open(path, 'wb') as f:
        f.write(magic)
        f.write(struct.pack('<I', calc_checksum))
        f.write(payload)

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

# Clean
make_file('/app/corpus/clean/c1.bin', [(1, b'abc'), (2, b'defg')])
make_file('/app/corpus/clean/c2.bin', [(10, b'x'*100)])

# Evil
make_file('/app/corpus/evil/e1.bin', [(1, b'')]) # Length == 0

# Truncated
payload2 = struct.pack('<BH', 1, 10) + b'abc'
csum2 = (sum(payload2) * 31) & 0xFFFFFFFF
with open('/app/corpus/evil/e2.bin', 'wb') as f:
    f.write(b'TLVM' + struct.pack('<I', csum2) + payload2)

make_file('/app/corpus/evil/e3.bin', [(0xFF, b'abc')]) # Type == 0xFF
make_file('/app/corpus/evil/e4.bin', [(1, b'abc')], bad_checksum=True) # Bad checksum
make_file('/app/corpus/evil/e5.bin', [(1, b'abc')], bad_magic=True) # Bad magic
EOF

    python3 /app/generate_corpus.py
    rm /app/generate_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
