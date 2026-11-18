#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    libprotobuf-dev \
    protobuf-compiler \
    zlib1g-dev \
    g++ \
    make \
    libgl1-mesa-glx \
    libglib2.0-0

pip3 install pytest opencv-python-headless numpy

mkdir -p /app
mkdir -p /home/user

# Generate the video
cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np

# 19 bytes of data + 1 byte padding = 20 bytes
data = bytes([0x0E, 0x00, 0x00, 0x00, 0x08, 0x64, 0x12, 0x03, 0x61, 0x70, 0x70, 0x1A, 0x01, 0xFF, 0x20, 0xEF, 0xBE, 0xAD, 0xDE, 0x00])

out = cv2.VideoWriter('/app/build_status.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100))
for byte in data:
    for i in range(8):
        bit = (byte >> (7 - i)) & 1
        frame = np.zeros((100, 100, 3), dtype=np.uint8)
        if bit:
            frame[0, 0] = [255, 255, 255]
        out.write(frame)
out.release()
EOF

python3 /app/generate_video.py

# Create telemetry.proto
cat << 'EOF' > /app/telemetry.proto
syntax = "proto3";
message Telemetry {
  uint64 timestamp = 1;
  string module_name = 2;
  bytes data = 3;
  uint32 crc32 = 4;
}
EOF

# Compile protobuf
cd /app
protoc --cpp_out=. telemetry.proto

# Create oracle program
cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <vector>
#include <string>
#include <algorithm>
#include <iomanip>
#include <zlib.h>
#include "telemetry.pb.h"

using namespace std;

int main() {
    vector<Telemetry> messages;
    while (true) {
        uint32_t len;
        if (!cin.read(reinterpret_cast<char*>(&len), 4)) break;
        string buf(len, '\0');
        if (!cin.read(&buf[0], len)) break;
        Telemetry t;
        if (t.ParseFromString(buf)) {
            uint32_t c = crc32(0L, Z_NULL, 0);
            c = crc32(c, reinterpret_cast<const Bytef*>(t.data().data()), t.data().size());
            if (c == t.crc32()) {
                messages.push_back(t);
            }
        }
    }
    sort(messages.begin(), messages.end(), [](const Telemetry& a, const Telemetry& b) {
        if (a.timestamp() != b.timestamp()) return a.timestamp() < b.timestamp();
        return a.module_name() < b.module_name();
    });
    for (const auto& t : messages) {
        cout << "[" << t.timestamp() << "] " << t.module_name() << ": ";
        for (unsigned char c : t.data()) {
            cout << hex << setw(2) << setfill('0') << (int)c;
        }
        cout << dec << "\n";
    }
    return 0;
}
EOF

g++ -std=c++20 -O2 /app/oracle.cpp /app/telemetry.pb.cc -o /app/oracle_telemetry_sorter -lprotobuf -lz

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
