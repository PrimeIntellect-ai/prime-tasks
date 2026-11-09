#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/service /home/user/uploads /home/user/.ssh

    echo "ssh-rsa AAAAB3Nza... fakekey" > /home/user/.ssh/id_rsa
    echo "Normal log entry" > /home/user/uploads/normal.log
    echo "Malicious log <script>alert(1)</script>" > /home/user/uploads/malicious.log

    cat << 'EOF' > /home/user/service/uploader.cpp
#include <iostream>
#include <fstream>
#include <string>

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <filename>\n";
        return 1;
    }

    std::string base_dir = "/home/user/uploads/";
    std::string filename = argv[1];
    std::string filepath = base_dir + filename;

    // TODO: Add path traversal prevention here

    std::ifstream file(filepath);
    if (!file) {
        std::cerr << "File not found\n";
        return 1;
    }

    std::string line;
    while (std::getline(file, line)) {
        if (line.find("<script>") != std::string::npos) {
            std::cout << "XSS detected: " << line << "\n";
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/access.log
192.168.1.15 - - [10/Oct/2023:13:55:36 -0700] "GET /upload?file=normal.log HTTP/1.1" 200 232
10.0.0.42 - - [10/Oct/2023:14:01:12 -0700] "GET /upload?file=../etc/passwd HTTP/1.1" 404 120
172.16.5.99 - - [10/Oct/2023:14:15:02 -0700] "GET /upload?file=../../.ssh/id_rsa HTTP/1.1" 200 401
192.168.1.15 - - [10/Oct/2023:14:20:11 -0700] "GET /upload?file=malicious.log HTTP/1.1" 200 511
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
