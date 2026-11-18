#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/ssh_keys
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UO0dkO7zNiK8/0F9kK9N/zW1r3yF service@internal" > /home/user/ssh_keys/service_ed25519.pub

    cat << 'EOF' > /home/user/auth_server.cpp
#include <iostream>
#include <string>
#include <fstream>
#include <sstream>
#include <iomanip>

std::string hex_decode(const std::string& hex) {
    std::string res;
    for (size_t i = 0; i < hex.length(); i += 2) {
        std::string byteString = hex.substr(i, 2);
        char byte = (char) strtol(byteString.c_str(), NULL, 16);
        res += byte;
    }
    return res;
}

std::string xor_cipher(const std::string& data, const std::string& key) {
    std::string res = data;
    for (size_t i = 0; i < data.size(); ++i) {
        res[i] ^= key[i % key.size()];
    }
    return res;
}

bool verify_token(const std::string& hex_token) {
    // 1. Read the key
    std::ifstream key_file("/home/user/ssh_keys/service_ed25519.pub");
    std::string key((std::istreambuf_iterator<char>(key_file)), std::istreambuf_iterator<char>());

    // 2. Decode and Decrypt
    std::string decoded = hex_decode(hex_token);
    std::string plaintext = xor_cipher(decoded, key);

    // 3. Parse token (Format: username|role|signature)
    size_t first_pipe = plaintext.find('|');
    size_t second_pipe = plaintext.find('|', first_pipe + 1);

    if (first_pipe == std::string::npos || second_pipe == std::string::npos) {
        return false;
    }

    std::string username = plaintext.substr(0, first_pipe);
    std::string role = plaintext.substr(first_pipe + 1, second_pipe - first_pipe - 1);
    std::string signature = plaintext.substr(second_pipe + 1);

    // 4. Vulnerability: Signature bypass
    if (signature == "NONE") {
        std::cout << "Debug bypass activated. Granted role: " << role << std::endl;
        return true; 
    }

    // (Normal signature verification would go here...)
    return false;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
