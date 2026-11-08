#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick g++ fonts-liberation
    pip3 install pytest

    mkdir -p /app

    # Generate the image
    convert -background white -fill black -pointsize 24 label:"WAL CONFIGURATION OPCODES v1.0\nOP_SET    = 0x1A\nOP_RM     = 0x1B\nOP_APPEND = 0x1C" /app/config_opcodes.png

    # Create oracle C++ code
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <fstream>
#include <map>
#include <string>
#include <cstdint>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::ifstream file(argv[1], std::ios::binary);
    if (!file) return 1;

    char magic[4];
    if (!file.read(magic, 4) || std::string(magic, 4) != "CWAL") return 0;

    std::map<std::string, std::string> state;

    while (file) {
        uint8_t op;
        if (!file.read((char*)&op, 1)) break;

        uint16_t keyLen;
        if (!file.read((char*)&keyLen, 2)) break;

        std::string key(keyLen, '\0');
        if (!file.read(&key[0], keyLen)) break;

        if (op == 0x1A || op == 0x1C) { // SET or APPEND
            uint16_t valLen;
            if (!file.read((char*)&valLen, 2)) break;

            std::string val(valLen, '\0');
            if (!file.read(&val[0], valLen)) break;

            if (op == 0x1A) {
                state[key] = val;
            } else {
                state[key] += val;
            }
        } else if (op == 0x1B) { // RM
            state.erase(key);
        } else {
            break; 
        }
    }

    for (const auto& pair : state) {
        std::cout << "[" << pair.first << "] -> [" << pair.second << "]\n";
    }
    return 0;
}
EOF

    # Compile the oracle
    g++ -O3 /tmp/oracle.cpp -o /app/oracle_wal_parser
    chmod +x /app/oracle_wal_parser

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
