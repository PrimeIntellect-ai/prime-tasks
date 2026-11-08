#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ git
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_decoder.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cstdint>

int main(int argc, char* argv[]) {
    if (argc != 3) return 1;
    std::ifstream in(argv[1], std::ios::binary);
    std::ofstream out(argv[2]);
    if (!in || !out) return 1;

    uint32_t magic;
    if (!in.read(reinterpret_cast<char*>(&magic), 4)) return 1;
    if (magic != 0xEFBEADDE) return 1; // 0xDE 0xAD 0xBE 0xEF little endian

    while (in) {
        uint8_t type;
        if (!in.read(reinterpret_cast<char*>(&type), 1)) break;
        if (type == 0xFF) break;

        uint16_t length;
        if (!in.read(reinterpret_cast<char*>(&length), 2)) break;

        if (type == 0x01) {
            std::string val(length, '\0');
            if (!in.read(&val[0], length)) break;
            out << "{\"type\": \"string\", \"value\": \"" << val << "\"}\n";
        } else if (type == 0x02) {
            int32_t val;
            if (!in.read(reinterpret_cast<char*>(&val), 4)) break;
            out << "{\"type\": \"int\", \"value\": " << val << "}\n";
        } else if (type == 0x03) {
            std::string val(length, '\0');
            if (!in.read(&val[0], length)) break;
            std::string key = "SECRET_KEY_992";
            for (size_t i = 0; i < length; ++i) {
                val[i] ^= key[i % key.length()];
            }
            out << "{\"type\": \"secure\", \"value\": \"" << val << "\"}\n";
        } else {
            in.seekg(length, std::ios::cur);
        }
    }
    return 0;
}
EOF
    g++ -O2 /app/legacy_decoder.cpp -o /app/legacy_decoder
    strip -s /app/legacy_decoder
    rm /app/legacy_decoder.cpp

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/pipeline_repo
    cd /home/user/pipeline_repo
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    echo "# Incomplete python decoder" > decoder.py
    git add decoder.py
    git commit -m "Initial commit"

    echo 'XOR_KEY="SECRET_KEY_992"' > keys.txt
    git add keys.txt
    git commit -m "Add keys"

    git rm keys.txt
    git commit -m "Remove keys"

    cat << 'EOF' > /app/generate_dat.py
import struct

def generate():
    with open('/app/hidden_test.dat', 'wb') as f:
        f.write(b'\xDE\xAD\xBE\xEF')

        # String
        s = b"Hello World"
        f.write(b'\x01' + struct.pack('<H', len(s)) + s)

        # Int
        f.write(b'\x02' + struct.pack('<H', 4) + struct.pack('<i', 42))

        # Encrypted
        s2 = b"SecureData123"
        key = b"SECRET_KEY_992"
        enc = bytes([s2[i] ^ key[i % len(key)] for i in range(len(s2))])
        f.write(b'\x03' + struct.pack('<H', len(enc)) + enc)

        # EOF
        f.write(b'\xFF')

generate()
EOF
    python3 /app/generate_dat.py
    /app/legacy_decoder /app/hidden_test.dat /app/ground_truth.jsonl

    chmod -R 777 /home/user
    chmod -R 777 /app
