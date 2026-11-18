#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        libssl-dev \
        espeak \
        ffmpeg \
        wget \
        curl

    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/intercepted_comms.wav "Seven Alpha Nine Foxtrot Three Bravo Two Charlie"

    # Create the oracle C++ source
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <string>
#include <vector>
#include <iomanip>
#include <openssl/sha.h>

int main(int argc, char* argv[]) {
    if (argc != 3) return 1;
    std::string key = argv[1];
    std::string payload_hex = argv[2];

    std::string salt = "0xDEADBEEF";
    std::string to_hash = key + salt;

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256((unsigned char*)to_hash.c_str(), to_hash.length(), hash);

    std::vector<uint8_t> payload;
    for (size_t i = 0; i < payload_hex.length(); i += 2) {
        std::string byteString = payload_hex.substr(i, 2);
        uint8_t byte = (uint8_t) strtol(byteString.c_str(), NULL, 16);
        payload.push_back(byte);
    }

    for (size_t i = 0; i < payload.size(); ++i) {
        payload[i] ^= hash[i % SHA256_DIGEST_LENGTH];
    }

    for (size_t i = 0; i < payload.size(); ++i) {
        std::cout << std::hex << std::uppercase << std::setfill('0') << std::setw(2) << (int)payload[i];
    }
    std::cout << std::endl;
    return 0;
}
EOF

    # Compile and strip the oracle
    g++ -O3 /app/oracle.cpp -o /app/oracle_decoder -lssl -lcrypto
    strip /app/oracle_decoder
    rm /app/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app
