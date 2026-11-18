#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y cmake build-essential libprotobuf-c-dev protobuf-c-compiler protobuf-compiler python3-protobuf

    mkdir -p /home/user/workspace
    cd /home/user/workspace

    cat << 'EOF' > config.proto
syntax = "proto3";
message ConfigData {
    string version = 1;
    bytes payload = 2;
}
EOF

    protoc-c --c_out=. config.proto

    cat << 'EOF' > generate.py
import config_pb2
import base64

msg = config_pb2.ConfigData()
msg.version = "2.10.5"
msg.payload = base64.b64encode(b"Migration to Python 3 complete! Protocol buffers and semver decoded.").decode('utf-8').encode('utf-8')

with open("config.bin", "wb") as f:
    f.write(msg.SerializeToString())
EOF

    protoc --python_out=. config.proto
    python3 generate.py

    cat << 'EOF' > CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(ConfigReader C)

set(CMAKE_C_STANDARD 99)

add_executable(app main.c config.pb-c.c)
# BUG: Missing linkage
EOF

    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "config.pb-c.h"

// BUGGY: Just uses strcmp, which fails for "2.10.5" vs "2.2.0"
int semver_compare(const char* v1, const char* v2) {
    return strcmp(v1, v2);
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;

    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t *buf = malloc(len);
    fread(buf, 1, len, f);
    fclose(f);

    ConfigData *msg = config_data__unpack(NULL, len, buf);
    if (!msg) return 1;

    FILE *out = fopen("/home/user/result.log", "w");
    if (semver_compare(msg->version, "2.0.0") >= 0) {
        // BUGGY: writes raw base64 instead of decoding
        fwrite(msg->payload.data, 1, msg->payload.len, out);
    } else {
        fprintf(out, "VERSION_TOO_OLD");
    }
    fclose(out);

    config_data__free_unpacked(msg, NULL);
    free(buf);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
