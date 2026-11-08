#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app

    # Create dummy video
    ffmpeg -f lavfi -i testsrc=duration=30:size=1280x720:rate=24 -c:v libx264 -pix_fmt yuv420p /app/screencast.mp4

    # Create docs_raw directory and files
    mkdir -p /home/user/docs_raw
    head -c 1000 /dev/urandom | base64 > /home/user/docs_raw/large1.md
    head -c 1000 /dev/urandom | base64 > /home/user/docs_raw/large2.md
    head -c 1000 /dev/urandom | base64 > /home/user/docs_raw/large3.md
    echo "small 1" > /home/user/docs_raw/small1.md
    echo "small 2" > /home/user/docs_raw/small2.md

    # Create oracle C++ source
    cat << 'EOF' > /app/oracle_tdoc_parser.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>
#include <string>

using namespace std;

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    ifstream f(argv[1], ios::binary);
    if (!f) {
        cout << "INVALID_HEADER\n";
        return 1;
    }

    char magic[4];
    if (f.read(magic, 4).gcount() != 4 || string(magic, 4) != "TDOC") {
        cout << "INVALID_HEADER\n";
        return 1;
    }

    char version;
    if (f.read(&version, 1).gcount() != 1 || version != 1) {
        cout << "INVALID_HEADER\n";
        return 1;
    }

    uint16_t record_count;
    if (f.read(reinterpret_cast<char*>(&record_count), 2).gcount() != 2) {
        cout << "INVALID_HEADER\n";
        return 1;
    }

    for (int i = 0; i < record_count; ++i) {
        uint32_t ts;
        if (f.read(reinterpret_cast<char*>(&ts), 4).gcount() != 4) {
            cout << "TRUNCATED\n";
            return 2;
        }

        uint16_t doc_id;
        if (f.read(reinterpret_cast<char*>(&doc_id), 2).gcount() != 2) {
            cout << "TRUNCATED\n";
            return 2;
        }

        uint16_t content_len;
        if (f.read(reinterpret_cast<char*>(&content_len), 2).gcount() != 2) {
            cout << "TRUNCATED\n";
            return 2;
        }

        vector<char> content(content_len);
        if (content_len > 0) {
            if (f.read(content.data(), content_len).gcount() != content_len) {
                cout << "TRUNCATED\n";
                return 2;
            }
        }

        uint32_t checksum = 0;
        for (int j = 0; j < content_len; ++j) {
            checksum += static_cast<uint8_t>(content[j]);
        }
        checksum %= 256;

        cout << "TS: " << ts << " | ID: " << doc_id << " | CHK: " << checksum << " | TXT: " << string(content.begin(), content.end()) << "\n";
    }

    return 0;
}
EOF

    g++ -O3 -std=c++17 /app/oracle_tdoc_parser.cpp -o /app/oracle_tdoc_parser

    chmod -R 777 /home/user
    chmod -R 777 /app
