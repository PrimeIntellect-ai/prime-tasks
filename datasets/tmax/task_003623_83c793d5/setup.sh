#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_auth.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <openssl/sha.h>
#include <iomanip>
#include <sstream>

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

int main(int argc, char* argv[], char* envp[]) {
    // Process isolation verification
    if (envp[0] != NULL) {
        std::cout << "Error: Environment not empty. Isolation failed." << std::endl;
        return 1;
    }

    std::ifstream f("/home/user/auth_config.txt");
    if (!f.is_open()) {
        std::cout << "Error: Missing config." << std::endl;
        return 1;
    }

    std::string stored_hash;
    f >> stored_hash;

    std::string pass;
    std::cin >> pass;

    std::string salt = "S@lt_90210_X";
    if (sha256(pass + salt) == stored_hash) {
        std::cout << "Access Granted" << std::endl;
    } else {
        std::cout << "Access Denied" << std::endl;
    }
    return 0;
}
EOF

    g++ -O2 /home/user/legacy_auth.cpp -o /home/user/legacy_auth -lcrypto
    rm /home/user/legacy_auth.cpp

    echo "0000000000000000000000000000000000000000000000000000000000000000" > /home/user/auth_config.txt

    chmod -R 777 /home/user
