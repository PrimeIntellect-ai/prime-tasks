#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick g++ fonts-dejavu
    pip3 install pytest

    mkdir -p /app

    # Fix imagemagick policy to allow writing png
    sed -i 's/rights="none" pattern="PNG"/rights="read|write" pattern="PNG"/' /etc/ImageMagick-6/policy.xml || true

    # Generate the policy screenshot
    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'Obsolete records to purge:'" -draw "text 20,100 'TxType: 0x8C, Status: 0x05'" /app/policy_screenshot.png

    # Write oracle compactor C++ code
    cat << 'EOF' > /app/oracle_compactor.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cstring>

using namespace std;

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    ifstream in(argv[1], ios::binary);
    if (!in) return 1;

    char magic[8];
    if (!in.read(magic, 8)) return 1;
    if (memcmp(magic, "WALv1\0\0\0", 8) != 0) return 1;

    ofstream out(argv[2], ios::binary);
    if (!out) return 1;
    out.write(magic, 8);

    while (in.peek() != EOF) {
        uint32_t len;
        if (!in.read((char*)&len, 4)) return 1;
        if (len < 6) return 1;
        uint8_t tx_type, status;
        if (!in.read((char*)&tx_type, 1)) return 1;
        if (!in.read((char*)&status, 1)) return 1;

        vector<char> payload(len - 6);
        if (len - 6 > 0) {
            if (!in.read(payload.data(), len - 6)) return 1;
        }

        if (tx_type == 0x8C && status == 0x05) {
            continue;
        }

        out.write((char*)&len, 4);
        out.write((char*)&tx_type, 1);
        out.write((char*)&status, 1);
        if (len - 6 > 0) {
            out.write(payload.data(), len - 6);
        }
    }

    return 0;
}
EOF

    g++ -O3 /app/oracle_compactor.cpp -o /app/oracle_compactor
    rm /app/oracle_compactor.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
