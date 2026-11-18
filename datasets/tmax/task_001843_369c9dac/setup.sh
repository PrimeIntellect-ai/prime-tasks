#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ cargo gawk coreutils
    pip3 install pytest

    # Setup /app/mobile_signer
    mkdir -p /app
    cat << 'EOF' > /tmp/mobile_signer.c
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char** argv) {
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "sha256sum %s | awk '{print $1}'", argv[1]);
    system(cmd);
    return 0;
}
EOF
    gcc -O3 -s /tmp/mobile_signer.c -o /app/mobile_signer
    rm /tmp/mobile_signer.c

    # Setup /home/user/rust_eval
    mkdir -p /home/user/rust_eval/src
    cat << 'EOF' > /home/user/rust_eval/Cargo.toml
[package]
name = "evaluator"
version = "0.1.0"
edition = "2021"
EOF

    # Use base64 to avoid Apptainer interpreting double braces as build variables
    echo "dXNlIHN0ZDo6ZW52OwpmbiBwYXJzZShleHByOiBTdHJpbmcpIC0+IFN0cmluZyB7CiAgICBmb3JtYXQhKCJ7e1wicGFyc2VkX2V4cHJcIjogXCJ7fVwifX0iLCBleHByKQp9CmZuIG1haW4oKSB7CiAgICBsZXQgYXJnczogVmVjPFN0cmluZz4gPSBlbnY6OmFyZ3MoKS5jb2xsZWN0KCk7CiAgICBpZiBhcmdzLmxlbigpIDwgMiB7IHJldHVybjsgfQogICAgbGV0IGV4cHIgPSBhcmdzWzFdLmNsb25lKCk7CiAgICBsZXQgcmVzID0gcGFyc2UoZXhwcik7CiAgICAvLyBUaGUgZGVsaWJlcmF0ZSBib3Jyb3cgY2hlY2tlciBlcnJvcjoKICAgIHByaW50bG4hKCJFeHByZXNzaW9uOiB7fSIsIGV4cHIpOyAvLyBFcnJvcjogZXhwciBtb3ZlZCBpbnRvIHBhcnNlKCkKICAgIHByaW50bG4hKCJ7fSIsIHJlcyk7Cn0=" | base64 -d > /home/user/rust_eval/src/main.rs

    # Setup /home/user/cpp_cache
    mkdir -p /home/user/cpp_cache
    cat << 'EOF' > /home/user/cpp_cache/main.cpp
#include <iostream>
#include <string>
#include <cstring>
std::string compute_hash(const std::string& data) {
    char* buffer = new char[10]; // Deliberate small buffer
    for(size_t i=0; i<=data.length(); i++) { 
        buffer[i] = data[i]; // UB and buffer overflow
    }
    std::string res(buffer);
    return res + "_hashed";
}
int main(int argc, char** argv) {
    if(argc < 2) return 1;
    std::cout << compute_hash(argv[1]) << std::endl;
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
