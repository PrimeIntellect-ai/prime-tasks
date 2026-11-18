#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils ltrace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/validator.cpp
#include <iostream>
#include <string>

int main() {
    std::string line;
    bool has_csp = false;
    bool has_debug_cookie = false;

    while (std::getline(std::cin, line)) {
        if (line == "\r" || line == "") break;
        if (line.find("Content-Security-Policy: ") == 0) {
            if (line.find("unsafe-eval") != std::string::npos) {
                has_csp = true;
            }
        }
        if (line.find("Cookie: ") == 0) {
            if (line.find("SESSID=0xDEADBEEF") != std::string::npos) {
                has_debug_cookie = true;
            }
        }
    }

    if (has_csp && has_debug_cookie) {
        std::cout << "FLAG{csp_and_cookies_reversed}" << std::endl;
    } else {
        std::cout << "Access Denied." << std::endl;
    }
    return 0;
}
EOF

    g++ /tmp/validator.cpp -o /home/user/validator
    chmod +x /home/user/validator
    rm /tmp/validator.cpp

    chmod -R 777 /home/user
