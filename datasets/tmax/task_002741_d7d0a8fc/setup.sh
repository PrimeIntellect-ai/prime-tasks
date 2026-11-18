#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake g++ make libssl-dev
    pip3 install pytest

    # Create directories
    mkdir -p /app/custom-jwt-cpp-1.0/include/jwt-cpp
    mkdir -p /opt/oracle

    # Create broken CMakeLists.txt
    cat << 'EOF' > /app/custom-jwt-cpp-1.0/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(jwt-cpp)

if(NOT "$ENV{ALLOW_INSECURE_ALGS}" STREQUAL "1")
    message(FATAL_ERROR "Insecure algorithms not allowed. Build aborted.")
endif()

add_library(jwt-cpp INTERFACE)
target_include_directories(jwt-cpp INTERFACE include/bad_path)
EOF

    # Create broken Makefile wrapper
    cat << 'EOF' > /app/custom-jwt-cpp-1.0/Makefile
all:
	unset ALLOW_INSECURE_ALGS && mkdir -p build && cd build && cmake .. && make
EOF

    # Create mocked jwt.h
    cat << 'EOF' > /app/custom-jwt-cpp-1.0/include/jwt-cpp/jwt.h
#pragma once
#include <string>
#include <stdexcept>

namespace jwt {
    struct decoded_jwt {
        std::string header;
        std::string payload;
        std::string signature;
    };

    inline decoded_jwt decode(const std::string& token) {
        decoded_jwt jwt;
        auto first_dot = token.find('.');
        if (first_dot == std::string::npos) throw std::runtime_error("malformed");
        auto second_dot = token.find('.', first_dot + 1);
        if (second_dot == std::string::npos) throw std::runtime_error("malformed");

        jwt.header = token.substr(0, first_dot);
        jwt.payload = token.substr(first_dot + 1, second_dot - first_dot - 1);
        jwt.signature = token.substr(second_dot + 1);
        return jwt;
    }
}
EOF

    # Create oracle binary (using Python script executable)
    cat << 'EOF' > /opt/oracle/token_analyzer_oracle
#!/usr/bin/env python3
import sys
import base64
import json
import hashlib

def main():
    if len(sys.argv) != 2:
        print("MALFORMED")
        sys.exit(2)
    token = sys.argv[1]
    parts = token.split('.')
    if len(parts) != 3:
        print("MALFORMED")
        sys.exit(2)

    try:
        header_raw = base64.urlsafe_b64decode(parts[0] + '=' * (-len(parts[0]) % 4))
        payload_raw = base64.urlsafe_b64decode(parts[1] + '=' * (-len(parts[1]) % 4))
        header = json.loads(header_raw)
        payload = json.loads(payload_raw)
    except Exception:
        print("MALFORMED")
        sys.exit(2)

    alg = header.get("alg", "")
    role = payload.get("role", "")

    if str(alg).lower() == "none" and role == "admin":
        h = hashlib.sha256(payload_raw).hexdigest()
        print(h)
        sys.exit(0)
    else:
        print("INVALID")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF
    chmod +x /opt/oracle/token_analyzer_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
