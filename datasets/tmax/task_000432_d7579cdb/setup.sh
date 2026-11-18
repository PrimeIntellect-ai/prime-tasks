#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip protobuf-compiler libprotobuf-dev g++ gcc ffmpeg
pip3 install pytest protobuf

mkdir -p /app/src

# Create the buggy parser.c
cat << 'EOF' > /app/src/parser.c
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    uint32_t id;
    uint32_t flags;
    char* payload;
} CArtifact;

// BUGGY VERSION: Missing bounds checks, off-by-one error, memory leak if malloc fails
int parse_header(const uint8_t* data, size_t len, CArtifact* out) {
    if (len < 5) return -1;
    out->id = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
    out->flags = data[4];

    size_t payload_len = len - 5;
    out->payload = (char*)malloc(payload_len); // off-by-one bug: missing null terminator
    memcpy(out->payload, data + 5, payload_len);
    // memory leak: if later operations fail, payload is never freed.
    return 0;
}

void free_artifact(CArtifact* art) {
    if (art->payload) {
        free(art->payload);
        art->payload = NULL;
    }
}
EOF

# Create the proto file for the oracle
cat << 'EOF' > /app/artifact.proto
syntax = "proto3";
message ArtifactHeader {
  uint32 id = 1;
  uint32 flags = 2;
  string payload = 3;
}
EOF

# Compile proto for oracle
cd /app
protoc --cpp_out=. artifact.proto

# Create the oracle parser
cat << 'EOF' > /app/oracle_parser.cpp
#include <iostream>
#include <vector>
#include <string>
#include "artifact.pb.h"

using namespace std;

int main() {
    vector<uint8_t> data;
    uint8_t byte;
    while (cin.read(reinterpret_cast<char*>(&byte), 1)) {
        data.push_back(byte);
    }

    if (data.size() < 5) return 1;

    ArtifactHeader header;
    uint32_t id = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
    uint32_t flags = data[4];

    header.set_id(id);
    header.set_flags(flags);

    if (data.size() > 5) {
        string payload(reinterpret_cast<char*>(data.data() + 5), data.size() - 5);
        header.set_payload(payload);
    } else {
        header.set_payload("");
    }

    string out;
    header.SerializeToString(&out);
    cout << out;

    return 0;
}
EOF

# Compile oracle parser
g++ -O2 /app/oracle_parser.cpp /app/artifact.pb.cc -o /app/oracle_parser -lprotobuf -lpthread
chmod +x /app/oracle_parser

# Generate the telemetry video losslessly
mkdir -p /tmp/frames
cat << 'EOF' > /tmp/gen_frames.py
import os

text = """syntax = "proto3";
message ArtifactHeader {
  uint32 id = 1;
  uint32 flags = 2;
  string payload = 3;
}
"""

for i, char in enumerate(text):
    val = ord(char)
    with open(f"/tmp/frames/frame_{i:04d}.pgm", "w") as f:
        f.write(f"P2\n128 128\n255\n")
        for _ in range(128):
            f.write(f"{val} " * 128 + "\n")
EOF

python3 /tmp/gen_frames.py
ffmpeg -framerate 10 -i /tmp/frames/frame_%04d.pgm -c:v libx264rgb -crf 0 /app/telemetry.mp4

# Clean up build files
rm -rf /tmp/frames /tmp/gen_frames.py /app/artifact.proto /app/artifact.pb.cc /app/artifact.pb.h /app/oracle_parser.cpp

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
