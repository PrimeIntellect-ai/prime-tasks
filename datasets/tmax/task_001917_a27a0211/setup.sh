#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make gdb
pip3 install pytest

mkdir -p /home/user/malware_analysis
cd /home/user/malware_analysis

cat << 'EOF' > utils.h
#ifndef UTILS_H
#define UTILS_H
void log_action(const char* msg);
#endif
EOF

cat << 'EOF' > utils.cpp
#include "utils.h"
#include <iostream>

void log_action(const char* msg) {
    // Simulated logging
}
EOF

cat << 'EOF' > decoder.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cstring>
#include "utils.h"

int decode_payload(const char* payload, int total_len) {
    if (total_len < 3) return -1;
    char type = payload[0];
    short len;
    memcpy(&len, payload + 1, sizeof(short));

    // Security check - bypassed due to signedness if len is negative
    if (len > total_len - 3) {
        return -1;
    }

    char buffer[1024];
    // Crash occurs here due to massive size_t conversion
    memcpy(buffer, payload + 3, len);

    log_action("Payload decoded");
    return 0;
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::ifstream file(argv[1], std::ios::binary | std::ios::ate);
    if (!file) return 1;
    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);
    std::vector<char> buffer(size);
    if (file.read(buffer.data(), size)) {
        return decode_payload(buffer.data(), size);
    }
    return 1;
}
EOF

cat << 'EOF' > Makefile
CXX = g++
CXXFLAGS = -g -Wall

decoder: decoder.cpp
	$(CXX) $(CXXFLAGS) -o decoder decoder.cpp

clean:
	rm -f decoder
EOF

python3 -c "open('crash.bin', 'wb').write(b'\x01\xFF\xFF\x41')"

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
