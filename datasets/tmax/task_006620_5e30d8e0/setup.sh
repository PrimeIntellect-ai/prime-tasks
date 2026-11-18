#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ gdb
pip3 install pytest

mkdir -p /home/user/telemetry_service

cat << 'EOF' > /home/user/telemetry_service/main.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>

struct Packet {
    uint32_t magic;
    double sensor_val;
};

void process_packet(const Packet& p) {
    std::vector<int> history_buffer(100, 0);

    // Flaw: Negative values or massive values cause out-of-bounds access.
    // The cast to int truncates, but negative values will wrap/crash.
    int index = static_cast<int>(p.sensor_val * 10.0);

    history_buffer[index] = 1; // Segmentation fault occurs here

    std::cout << "Processed index: " << index << std::endl;
}

int main(int argc, char** argv) {
    if(argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <input_file>" << std::endl;
        return 1;
    }
    std::ifstream ifs(argv[1], std::ios::binary);
    if(!ifs) {
        std::cerr << "Failed to open file." << std::endl;
        return 1;
    }

    Packet p;
    ifs.read(reinterpret_cast<char*>(&p), sizeof(p));

    if (p.magic != 0xDEADBEEF) {
        std::cerr << "Invalid magic." << std::endl;
        return 1;
    }

    process_packet(p);
    return 0;
}
EOF

g++ -g -o /home/user/telemetry_service/telemetry /home/user/telemetry_service/main.cpp

python3 -c "
import struct
with open('/home/user/telemetry_service/input.bin', 'wb') as f:
    f.write(struct.pack('<Id', 0xDEADBEEF, -1.5))
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
