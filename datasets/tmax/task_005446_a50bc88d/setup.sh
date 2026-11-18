#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential wget pkg-config libsodium-dev
    pip3 install pytest

    mkdir -p /app

    # Create the oracle program
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <string>
#include <vector>
#include <iomanip>
#include <sstream>
#include <sodium.h>
#include <cstring>

std::vector<unsigned char> hex_to_bytes(const std::string& hex) {
    std::vector<unsigned char> bytes;
    for (size_t i = 0; i < hex.length(); i += 2) {
        std::string byteString = hex.substr(i, 2);
        unsigned char byte = (unsigned char) strtol(byteString.c_str(), NULL, 16);
        bytes.push_back(byte);
    }
    return bytes;
}

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    if (sodium_init() < 0) return 1;

    std::string ciphertext_hex = argv[1];
    std::string key_prefix_hex = argv[2];

    std::vector<unsigned char> ciphertext = hex_to_bytes(ciphertext_hex);
    std::vector<unsigned char> key_prefix = hex_to_bytes(key_prefix_hex);

    if (key_prefix.size() != 2) return 1;

    unsigned char key[crypto_secretbox_KEYBYTES];
    memset(key, 0, sizeof(key));
    key[0] = key_prefix[0];
    key[1] = key_prefix[1];

    unsigned char nonce[crypto_secretbox_NONCEBYTES];
    memset(nonce, 0, sizeof(nonce));

    std::vector<unsigned char> decrypted(ciphertext.size() - crypto_secretbox_MACBYTES);

    for (int i = 0; i <= 0xFFFF; ++i) {
        key[2] = (i >> 8) & 0xFF;
        key[3] = i & 0xFF;

        if (crypto_secretbox_open_easy(decrypted.data(), ciphertext.data(), ciphertext.size(), nonce, key) == 0) {
            std::string plaintext((char*)decrypted.data(), decrypted.size());
            if (plaintext.substr(0, 8) == "HTTP/1.1") {
                std::cout << plaintext;
                return 0;
            }
        }
    }

    std::cerr << "DECRYPTION FAILED" << std::endl;
    return 1;
}
EOF

    g++ -O3 /tmp/oracle.cpp -o /app/oracle_bin -lsodium
    strip /app/oracle_bin
    rm /tmp/oracle.cpp

    # Download and sabotage libsodium source
    wget https://github.com/jedisct1/libsodium/releases/download/1.0.18-RELEASE/libsodium-1.0.18.tar.gz -O /tmp/libsodium.tar.gz
    tar -xzf /tmp/libsodium.tar.gz -C /app
    rm /tmp/libsodium.tar.gz

    # Sabotage the file at line 25
    sed -i '25i #error "Forensics blocked"' /app/libsodium-1.0.18/src/libsodium/crypto_secretbox/crypto_secretbox.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
