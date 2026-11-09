#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs
    mkdir -p /home/user/src
    mkdir -p /home/user/bin

    cat << 'EOF' > /home/user/logs/ingest.log
[2023-10-14 10:00:00] INGEST ID=REQ-1001 PAYLOAD=03414243
[2023-10-14 10:00:01] INGEST ID=REQ-1002 PAYLOAD=0158
[2023-10-14 10:00:02] INGEST ID=REQ-1003 PAYLOAD=02595A
[2023-10-14 10:00:03] INGEST ID=REQ-1004 PAYLOAD=FF41
[2023-10-14 10:00:04] INGEST ID=REQ-1005 PAYLOAD=0142
EOF

    cat << 'EOF' > /home/user/logs/processor.log
[2023-10-14 10:00:00] START ID=REQ-1001
[2023-10-14 10:00:00] END ID=REQ-1001
[2023-10-14 10:00:01] START ID=REQ-1002
[2023-10-14 10:00:01] END ID=REQ-1002
[2023-10-14 10:00:02] START ID=REQ-1003
[2023-10-14 10:00:02] END ID=REQ-1003
[2023-10-14 10:00:03] START ID=REQ-1004
EOF

    cat << 'EOF' > /home/user/src/telemetry_parser.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>

void process_record(const std::vector<uint8_t>& data) {
    if (data.empty()) return;

    uint32_t items = data[0];
    uint32_t processed = 0;
    size_t offset = 1;

    while (processed < items) {
        if (offset >= data.size()) {
            // BUG: corrupted length leads to missing break on EOF, causing livelock
            continue;
        }
        // simulate processing
        volatile uint8_t val = data[offset];
        (void)val;

        offset++;
        processed++;
    }
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <binary_file>\n";
        return 1;
    }

    std::ifstream file(argv[1], std::ios::binary | std::ios::ate);
    if (!file) return 1;

    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);

    std::vector<uint8_t> buffer(size);
    if (file.read((char*)buffer.data(), size)) {
        process_record(buffer);
    }

    return 0;
}
EOF

    chmod -R 777 /home/user
