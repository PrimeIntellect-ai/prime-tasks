#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git g++
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data_pipeline
cd /home/user/data_pipeline

git init
git config user.name "Dev"
git config user.email "dev@example.com"

cat << 'EOF' > logs.txt
[INFO] user: alice, token: tk_abc12345, status: active
[INFO] user: bob, token: tk_def67890, status: active
[INFO] user: charlie, token: tk_ghi11223, status: inactive
EOF

cat << 'EOF' > config.h
#pragma once
#include <string>

const std::string SECRET_KEY = "sk_live_9a8b7c6d5e4f";
EOF

cat << 'EOF' > parser.cpp
#include <iostream>
#include <fstream>
#include <string>

int main() {
    std::ifstream infile("logs.txt");
    std::ofstream outfile("output.txt");
    std::string line;

    while (std::getline(infile, line)) {
        size_t start = line.find("token: ");
        if (start != std::string::npos) {
            start += 7; // "token: " is 7 chars
            size_t end = line.find(",", start);
            if (end != std::string::npos) {
                // BUG: off-by-one error, includes the comma
                std::string token = line.substr(start, end - start + 1);
                outfile << token << "\n";
            }
        }
    }
    return 0;
}
EOF

git add .
git commit -m "Initial commit with log parser"

cat << 'EOF' > config.h
#pragma once
#include <string>

// Removed secret key for security
const std::string SECRET_KEY = "";
EOF

git add config.h
git commit -m "Remove hardcoded secret key"

chown -R user:user /home/user
chmod -R 777 /home/user
