#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/pentest_data

    cat << 'EOF' > /home/user/pentest_data/malicious_hashes.txt
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
7096c429676e65a0c325bd7297eef9e7c11f7cbe5de31ce3edbde217592cf3f5
8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92
EOF

    cat << 'EOF' > /home/user/pentest_data/access.log
192.168.1.50 - - [12/Oct/2023:13:55:36] "GET /api/status HTTP/1.1" 200
10.0.0.5 - - [12/Oct/2023:13:56:01] "GET /api/auth?payload=171a1313102008100d131b HTTP/1.1" 200
172.16.23.4 - - [12/Oct/2023:13:58:22] "GET /api/auth?payload=0d1c1a200f1e0613101e1b201a071a1c1a0b1a HTTP/1.1" 200
192.168.1.100 - - [12/Oct/2023:14:01:10] "GET /api/auth?payload=1e1b121611201310181611 HTTP/1.1" 200
EOF

    cat << 'EOF' > /home/user/pentest_data/decoder.cpp
#include <iostream>
#include <string>
#include <vector>

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    std::string hex_str = argv[1];
    std::string decoded = "";

    // Bug: loop only goes halfway!
    for (size_t i = 0; i < hex_str.length() / 4; i++) {
        std::string byteString = hex_str.substr(i * 2, 2);
        char byte = (char) strtol(byteString.c_str(), NULL, 16);
        decoded += (byte ^ 0x7F);
    }
    std::cout << decoded;
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
