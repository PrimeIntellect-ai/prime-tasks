#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest grpcio grpcio-tools protobuf

    mkdir -p /home/user/build_tools
    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/build_tools/manifest_parser.cpp
#include <iostream>
#include <cstring>

void parse_manifest(const char* input) {
    char buffer[10]; 
    // Bug 1: Buffer overflow
    strcpy(buffer, input); 

    // Bug 2: Memory leak
    int* data = new int[100];
    data[0] = 1;

    std::cout << "Parsed: " << buffer << std::endl;
}

int main() {
    const char* test_input = "Manifest_V1";
    parse_manifest(test_input);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
