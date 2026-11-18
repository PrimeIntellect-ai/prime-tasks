#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create legacy binary source and compile it
    cat << 'EOF' > legacy.cpp
#include <iostream>
#include <string>

const char* SECRET_PWD = "AUTH_PWD:Str0ngL3gacyP@ssw0rd!2023";

int main() {
    std::cout << "Legacy worker running..." << std::endl;
    return 0;
}
EOF
    g++ -std=c++17 legacy.cpp -o legacy_auth_worker
    rm legacy.cpp

    # Create new vulnerable source
    cat << 'EOF' > new_auth_worker.cpp
#include <iostream>
#include <string>
#include <cstdlib>

// Secure mock function provided to the user
bool safe_ping(const std::string& host) {
    // In a real scenario, this would use raw sockets or a safe library
    if (host.find_first_of(";&|`$") != std::string::npos) return false;
    return true;
}

bool check_host(const std::string& host) {
    // VULNERABILITY: Command Injection
    std::string cmd = "ping -c 1 " + host + " > /dev/null 2>&1";
    int result = system(cmd.c_str());
    return (result == 0);
}

int main() {
    std::string test_host = "127.0.0.1";
    if (check_host(test_host)) {
        std::cout << "Host is up!" << std::endl;
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
