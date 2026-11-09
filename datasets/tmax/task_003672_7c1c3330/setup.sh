#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create secret file
    echo "FLAG{cwe_78_c00kie_pwn}" > /home/user/secret.txt
    chmod 644 /home/user/secret.txt

    # Create permission checker script
    echo '#!/bin/bash' > /home/user/check_perms.sh
    echo 'echo "Checking perms for user: $1"' >> /home/user/check_perms.sh
    chmod +x /home/user/check_perms.sh

    # Create vulnerable process_req.cpp
    cat << 'EOF' > /home/user/process_req.cpp
#include <iostream>
#include <string>
#include <vector>
#include <cstdlib>

// Simple base64 decoder
std::string base64_decode(const std::string &in) {
    std::string out;
    std::vector<int> T(256, -1);
    for (int i = 0; i < 64; i++) T["ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[i]] = i;
    int val = 0, valb = -8;
    for (unsigned char c : in) {
        if (T[c] == -1) break;
        val = (val << 6) + T[c];
        valb += 6;
        if (valb >= 0) {
            out.push_back(char((val >> valb) & 0xFF));
            valb -= 8;
        }
    }
    return out;
}

int main() {
    std::string line;
    std::string cookie_val;
    while (std::getline(std::cin, line)) {
        if (line == "\r" || line.empty()) break;
        size_t pos = line.find("Cookie: session=");
        if (pos == 0) {
            cookie_val = line.substr(16);
            if (!cookie_val.empty() && cookie_val.back() == '\r') {
                cookie_val.pop_back();
            }
        }
    }

    if (!cookie_val.empty()) {
        std::string decoded = base64_decode(cookie_val);
        // VULNERABILITY: CWE-78 OS Command Injection
        std::string cmd = "/home/user/check_perms.sh " + decoded;
        system(cmd.c_str());
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
