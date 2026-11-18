#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <string>
#include <vector>
#include <sstream>
#include <iomanip>
#include <openssl/sha.h>

std::string sha256(const std::string str) {
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256_CTX sha256;
    SHA256_Init(&sha256);
    SHA256_Update(&sha256, str.c_str(), str.size());
    SHA256_Final(hash, &sha256);
    std::stringstream ss;
    for(int i = 0; i < SHA256_DIGEST_LENGTH; i++)
        ss << std::hex << std::setw(2) << std::setfill('0') << (int)hash[i];
    return ss.str();
}

int main() {
    std::string line;
    if (std::getline(std::cin, line)) {
        std::stringstream ss(line);
        std::string item;
        std::vector<std::string> tokens;
        while (std::getline(ss, item, ',')) {
            tokens.push_back(item);
        }
        if (tokens.size() == 5) {
            std::string email = tokens[3];
            size_t at_pos = email.find('@');
            std::string masked_email = email.substr(0, 2) + "***" + email.substr(at_pos);

            std::string phone = tokens[4];
            std::string masked_phone = "***-***-" + phone.substr(phone.length() - 4);

            std::cout << tokens[0] << "," << tokens[2] << "," << tokens[1] << "," 
                      << masked_email << "," << masked_phone << "," << sha256(email) << std::endl;
        }
    }
    return 0;
}
EOF

    g++ -O3 -std=c++17 /tmp/oracle.cpp -o /app/csv_processor_oracle -lcrypto
    strip /app/csv_processor_oracle
    rm /tmp/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
