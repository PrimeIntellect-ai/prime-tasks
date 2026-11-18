#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

cat << 'EOF' > /home/user/auth_backend.cpp
#include <iostream>
#include <string>
#include <iomanip>
#include <sstream>
#include <cstdlib>

// Redacted Web Server Context

std::string encrypt_token(const std::string& plaintext) {
    uint8_t state = 0x37; // Initial seed
    std::stringstream hex_stream;

    for (char c : plaintext) {
        // Linear stream cipher state update
        state = (state * 13 + 37) % 256;

        // XOR with current state
        uint8_t encrypted_char = static_cast<uint8_t>(c) ^ state;

        hex_stream << std::hex << std::setfill('0') << std::setw(2) << (int)encrypted_char;
    }
    return hex_stream.str();
}

void process_login(const std::string& username, const std::string& password) {
    std::string token = encrypt_token(password);

    // VULNERABILITY: Spawning a sub-process exposes the token in /proc/[pid]/cmdline
    std::string cmd = "./auth_helper " + username + " " + token;
    system(cmd.c_str());
}
EOF

cat << 'EOF' > /home/user/proc_logs.txt
[10:05:21] CMD: ./auth_helper guest 672e11
[10:12:44] CMD: /usr/sbin/cron
[10:15:02] CMD: ./auth_helper testuser 542b101188
[10:18:33] CMD: ./auth_helper admin a0221c1088b680ef8ad493a4c9aa9c93e3b2
[10:22:10] CMD: bash -c "rm -rf /tmp/cache*"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
