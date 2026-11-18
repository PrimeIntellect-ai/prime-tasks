#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_server.cpp
#include <iostream>
#include <string>
#include <sstream>
#include <iomanip>

const std::string SECRET_KEY = "LEGACY_KEY_884";

std::string compute_hash(const std::string& data, const std::string& key) {
    std::string out = "";
    for(size_t i = 0; i < data.length(); ++i) {
        char c = data[i] ^ key[i % key.length()];
        char hex[3];
        snprintf(hex, sizeof(hex), "%02x", (unsigned char)c);
        out += hex;
    }
    return out;
}

int main() {
    std::string line;
    std::string cookie_header = "";

    // Read headers
    while (std::getline(std::cin, line)) {
        if (line == "\r" || line == "") break;
        if (line.rfind("Cookie: ", 0) == 0) {
            cookie_header = line.substr(8);
            // remove trailing \r if present
            if (!cookie_header.empty() && cookie_header.back() == '\r') {
                cookie_header.pop_back();
            }
        }
    }

    if (cookie_header.empty()) {
        std::cout << "Access Denied: No Cookie\n";
        return 1;
    }

    size_t prefix_pos = cookie_header.find("session=");
    if (prefix_pos == std::string::npos) {
        std::cout << "Access Denied: Invalid Cookie Format\n";
        return 1;
    }

    std::string session_val = cookie_header.substr(prefix_pos + 8);
    size_t colon_pos = session_val.find(":");
    if (colon_pos == std::string::npos) {
        std::cout << "Access Denied: Missing Signature\n";
        return 1;
    }

    std::string data = session_val.substr(0, colon_pos);
    std::string hash = session_val.substr(colon_pos + 1);

    std::string expected_hash = compute_hash(data, SECRET_KEY);

    if (hash != expected_hash) {
        std::cout << "Access Denied: Invalid Signature\n";
        return 1;
    }

    if (data == "role=admin") {
        std::cout << "Access Granted: Admin\n";
    } else {
        std::cout << "Access Granted: User\n";
    }

    return 0;
}
EOF

    cat << 'EOF' > /home/user/traffic.log
192.168.1.10 session=role=user:3e2a2324061c1c1e2d
10.0.0.55 session=role=user:3e2a2324061c1c1e2d
172.16.0.4 session=role=admin:3e2a2324061c1c1e2d
192.168.1.101 session=role=user:3e2a2324061c1c1e2d
203.0.113.8 session=role=admin:000000000000000000
198.51.100.2 session=role=user:abcdef1234567890
EOF

    chmod -R 777 /home/user
