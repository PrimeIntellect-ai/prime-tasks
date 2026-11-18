#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bubblewrap g++ make
    pip3 install pytest

    mkdir -p /home/user/auth_service

    cat << 'EOF' > /home/user/auth_service/auth_server.cpp
#include <iostream>
#include <string>

// Helper to mock base64 decode for the sake of the exercise
std::string mock_b64_decode(const std::string& input) {
    return input; // Assuming plain text for the mock to simplify dependencies
}

bool verify_cert_chain(int chain_depth) {
    // TODO: Require at least a chain depth of 2 (Root CA -> Intermediate CA -> Leaf)
    return true; // Vulnerability: blindly trusts
}

bool validate_token(const std::string& token, int cert_chain_depth) {
    size_t first_dot = token.find('.');
    size_t second_dot = token.find('.', first_dot + 1);

    if (first_dot == std::string::npos || second_dot == std::string::npos) {
        return false;
    }

    std::string header = token.substr(0, first_dot);
    std::string payload = token.substr(first_dot + 1, second_dot - first_dot - 1);
    std::string signature = token.substr(second_dot + 1);

    // VULNERABILITY: alg=none bypass
    if (header.find("\"alg\":\"none\"") != std::string::npos || 
        header.find("\"alg\":\"NONE\"") != std::string::npos) {
        return true; // Bypasses signature verification entirely
    }

    if (!verify_cert_chain(cert_chain_depth)) {
        return false;
    }

    // Mock signature verification
    if (signature == "VALID_SIG") {
        return true;
    }

    return false;
}

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    std::string token = argv[1];

    if (validate_token(token, 1)) {
        std::cout << "ACCESS GRANTED\n";
        return 0;
    } else {
        std::cout << "ACCESS DENIED\n";
        return 1;
    }
}
EOF

    cat << 'EOF' > /home/user/auth_service/Makefile
all:
	g++ -O2 -std=c++11 auth_server.cpp -o auth_server
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
