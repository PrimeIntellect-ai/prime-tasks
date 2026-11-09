#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ binutils openssl
    pip3 install pytest

    mkdir -p /home/user/evidence
    cd /home/user/evidence

    # 1. Generate fake certificate chain
    mkdir -p certs
    cd certs
    # Root CA
    openssl req -x509 -sha256 -days 3650 -nodes -newkey rsa:2048 -subj "/C=US/O=DarkWeb/CN=Rogue Root CA" -keyout root.key -out root.crt
    # Leaf Cert
    openssl req -new -nodes -newkey rsa:2048 -subj "/C=US/O=Malware/CN=malware.c2.local" -keyout leaf.key -out leaf.csr
    openssl x509 -req -in leaf.csr -CA root.crt -CAkey root.key -CAcreateserial -out leaf.crt -days 365 -sha256
    # Combine into chain
    cat leaf.crt root.crt > ../chain.pem
    cd ..
    rm -rf certs

    # 2. Create the dummy ELF and inject the certificate section
    cat << 'EOF' > dummy.c
int main() { return 0; }
EOF
    gcc dummy.c -o dummy.elf
    objcopy --add-section .evil_cert=chain.pem dummy.elf dropper.elf
    rm dummy.c dummy.elf

    # 3. Create the C++ encryption script to generate stolen_data.enc
    cat << 'EOF' > encrypt.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>

int main() {
    uint32_t state = 0x5A9F2C1B; // The secret key/seed
    std::string plaintext = "CONFIDENTIAL: The main server backdoor password is 'RogueAccess2024!'. Do not share.";

    std::ofstream out_enc("stolen_data.enc", std::ios::binary);
    for (char c : plaintext) {
        uint8_t key_byte = (state >> 24) & 0xFF;
        uint8_t cipher_byte = c ^ key_byte;
        out_enc.write(reinterpret_cast<const char*>(&cipher_byte), 1);
        state = (1103515245 * state + 12345) % 4294967296ULL;
    }
    out_enc.close();

    std::ofstream out_known("known_plaintext.bin", std::ios::binary);
    out_known.write(plaintext.c_str(), 12);
    out_known.close();

    return 0;
}
EOF
    g++ encrypt.cpp -o encrypt_bin
    ./encrypt_bin
    rm encrypt.cpp encrypt_bin chain.pem

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/evidence
    chmod -R 777 /home/user
