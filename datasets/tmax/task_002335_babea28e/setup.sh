#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cmake make
    pip3 install pytest

    mkdir -p /home/user/opt/mock_libs
    mkdir -p /home/user/workspace/auth_module

    cat << 'EOF' > /tmp/mock_waf.cpp
#include <string>
#include <iostream>

extern "C" {
    bool validate_payload(const char* payload) {
        std::string p(payload);
        if (p.length() != 16) return false;
        if (p.substr(0, 5) != "admin") return false;
        int sum = 0;
        for (int i = 5; i < 16; i++) {
            sum += p[i];
        }
        return sum == 1000;
    }
}
EOF

    g++ -shared -fPIC /tmp/mock_waf.cpp -o /home/user/opt/mock_libs/libmock_waf.so
    rm /tmp/mock_waf.cpp

    cat << 'EOF' > /home/user/workspace/auth_module/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(AuthModule)
set(CMAKE_CXX_STANDARD 17)

add_executable(auth_test auth_test.cpp)
EOF

    cat << 'EOF' > /home/user/workspace/auth_module/auth_test.cpp
#include <iostream>
#include <string>
#include <cstring>

extern "C" bool validate_payload(const char* payload);

// Memory leak here: allocated buffer is not freed if token is "malformed"
bool process_token(const std::string& token) {
    char* buffer = new char[256];
    std::strncpy(buffer, token.c_str(), 255);
    buffer[255] = '\0';

    if (token == "malformed") {
        return false;
    }

    bool result = (std::strlen(buffer) > 0);
    delete[] buffer;
    return result;
}

std::string generate_attack_payload() {
    return "";
}

int main() {
    bool ok = true;
    if (process_token("malformed")) {
        std::cout << "Test 1 failed" << std::endl;
        ok = false;
    }

    std::string payload = generate_attack_payload();
    if (!validate_payload(payload.c_str())) {
        std::cout << "Test 2 failed: Invalid payload" << std::endl;
        ok = false;
    }

    if (ok) {
        std::cout << "All tests passed!" << std::endl;
        return 0;
    }
    return 1;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
