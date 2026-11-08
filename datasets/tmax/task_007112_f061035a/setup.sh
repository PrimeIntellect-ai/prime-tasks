#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make
pip3 install pytest

mkdir -p /home/user/telemetry
cd /home/user/telemetry

cat << 'EOF' > telemetry_processor.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>
#include <stdexcept>

// Decodes a base-128 varint
uint64_t parse_varint(const std::vector<uint8_t>& buf, size_t& offset) {
    uint64_t value = 0;
    int shift = 0;
    while (true) {
        // BUG: No bounds checking on 'offset' vs 'buf.size()'
        uint8_t byte = buf[offset++];
        value |= static_cast<uint64_t>(byte & 0x7F) << shift;
        if ((byte & 0x80) == 0) {
            break;
        }
        shift += 7;
    }
    return value;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <binary_file>\n";
        return 1;
    }

    std::ifstream file(argv[1], std::ios::binary | std::ios::ate);
    if (!file) {
        std::cerr << "Failed to open file.\n";
        return 1;
    }

    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);

    std::vector<uint8_t> buffer(size);
    if (file.read(reinterpret_cast<char*>(buffer.data()), size)) {
        size_t offset = 0;
        uint64_t total_sum = 0;

        try {
            while (offset < buffer.size()) {
                uint8_t record_type = buffer[offset++];
                if (record_type == 0x01) {
                    uint64_t val = parse_varint(buffer, offset);
                    total_sum += val;
                } else if (record_type == 0x02) {
                    uint64_t val = parse_varint(buffer, offset);
                    total_sum -= val;
                } else {
                    throw std::runtime_error("Unknown record type");
                }
            }
            std::cout << "Processing Complete. Total Sum: " << total_sum << std::endl;
        } catch (const std::exception& e) {
            std::cerr << "Error: " << e.what() << "\n";
            std::cout << "Processing Aborted. Total Sum: " << total_sum << std::endl;
        }
    }
    return 0;
}
EOF

cat << 'EOF' > Makefile
CXX=g++
CXXFLAGS=-O2 -Wall -std=c++14

all: telemetry_processor

telemetry_processor: telemetry_processor.cpp
	$(CXX) $(CXXFLAGS) -o telemetry_processor telemetry_processor.cpp

clean:
	rm -f telemetry_processor data.bin
EOF

cat << 'EOF' > generate_traffic.py
import struct
import random

def encode_varint(value):
    encoded = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            encoded.append(byte | 0x80)
        else:
            encoded.append(byte)
            break
    return encoded

def generate():
    random.seed(42)
    with open("data.bin", "wb") as f:
        total_expected = 0
        # Generate 5000 valid records
        for _ in range(5000):
            rtype = random.choice([1, 2])
            f.write(bytes([rtype]))
            val = random.randint(1, 10000)
            if rtype == 1:
                total_expected += val
            else:
                total_expected -= val
            f.write(encode_varint(val))

        # Write expected total out to a secret file just for verification context
        with open(".secret_expected.txt", "w") as sf:
            sf.write(str(total_expected))

        # Append malformed record (type 0x01, but varint never terminates)
        f.write(bytes([0x01]))
        f.write(bytes([0xFF, 0xFF, 0xFF, 0xFF, 0xFF])) # No MSB=0 byte

if __name__ == "__main__":
    generate()
EOF

chmod +x generate_traffic.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
