#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tesseract-ocr imagemagick
    pip3 install pytest

    mkdir -p /app

    # Generate the specification image
    cat << 'EOF' > /app/spec.txt
WAL Configuration Archive Format v1.0
-------------------------------------
File Header (6 bytes):
Magic Bytes: 0x57 0x41 0x4C 0x43 ("WALC")
Version: 0x01 0x00 (Little Endian 1)

Records (Variable length, repeats until EOF):
[1 byte] Operation Code:
   0x00 = ADD
   0x01 = DEL
   0x02 = MOD
[1 byte] Key Length (K)
[K bytes] Key String (ASCII)
[2 bytes] Value Length (V) - Little Endian UInt16
[V bytes] Value String (ASCII)

Notes:
- If header does not match exactly, abort immediately.
- If a record is truncated (EOF hit mid-record), silently stop parsing and output current valid state.
- Unrecognized Operation Codes immediately terminate parsing.
EOF

    # Imagemagick policy might prevent text to image, so update it or just use convert directly
    sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/g' /etc/ImageMagick-6/policy.xml || true
    convert -background white -fill black -font Courier -pointsize 14 text:/app/spec.txt /app/wal_spec.png

    # Write oracle C++ code
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <map>
#include <string>
#include <vector>
#include <cstdint>

using namespace std;

int main() {
    uint8_t header[6];
    if (fread(header, 1, 6, stdin) != 6) {
        cout << "INVALID FORMAT\n";
        return 1;
    }
    if (header[0] != 0x57 || header[1] != 0x41 || header[2] != 0x4C || header[3] != 0x43 ||
        header[4] != 0x01 || header[5] != 0x00) {
        cout << "INVALID FORMAT\n";
        return 1;
    }

    map<string, string> state;

    while (true) {
        uint8_t op;
        if (fread(&op, 1, 1, stdin) != 1) break;
        if (op > 2) break; // Unrecognized op code

        uint8_t klen;
        if (fread(&klen, 1, 1, stdin) != 1) break;

        vector<char> key(klen);
        if (klen > 0 && fread(key.data(), 1, klen, stdin) != klen) break;

        uint8_t vlen_buf[2];
        if (fread(vlen_buf, 1, 2, stdin) != 2) break;
        uint16_t vlen = vlen_buf[0] | (vlen_buf[1] << 8);

        vector<char> val(vlen);
        if (vlen > 0 && fread(val.data(), 1, vlen, stdin) != vlen) break;

        string k(key.begin(), key.end());
        string v(val.begin(), val.end());

        if (op == 0x00) { // ADD
            state[k] = v;
        } else if (op == 0x01) { // DEL
            state.erase(k);
        } else if (op == 0x02) { // MOD
            if (state.count(k)) {
                state[k] = v;
            }
        }
    }

    for (auto const& [k, v] : state) {
        cout << k << ":" << v << "\n";
    }

    return 0;
}
EOF

    g++ -O2 /app/oracle.cpp -o /app/oracle_wal_tracker
    chmod +x /app/oracle_wal_tracker

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
