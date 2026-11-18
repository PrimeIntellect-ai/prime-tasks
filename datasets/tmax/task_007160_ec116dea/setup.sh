#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/ticket_8492

    cat << 'EOF' > /home/user/ticket_8492/Makefile
wal_daemon: main.cpp wal_parser.cpp
	g++ -g -O0 -o wal_daemon main.cpp wal_parser.cpp
EOF

    cat << 'EOF' > /home/user/ticket_8492/wal_parser.h
#ifndef WAL_PARSER_H
#define WAL_PARSER_H

#include <string>
#include <vector>

struct Record {
    char type;
    std::string payload;
};

class WalParser {
public:
    std::vector<Record> parse(const std::string& filepath);
private:
    void parse_record(const std::vector<unsigned char>& data, size_t offset, std::vector<Record>& records);
};

#endif
EOF

    cat << 'EOF' > /home/user/ticket_8492/wal_parser.cpp
#include "wal_parser.h"
#include <fstream>
#include <iostream>

std::vector<Record> WalParser::parse(const std::string& filepath) {
    std::ifstream file(filepath, std::ios::binary);
    std::vector<unsigned char> data((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());

    std::vector<Record> records;
    if (!data.empty()) {
        parse_record(data, 0, records);
    }
    return records;
}

void WalParser::parse_record(const std::vector<unsigned char>& data, size_t offset, std::vector<Record>& records) {
    if (offset >= data.size()) {
        return;
    }

    char type = data[offset];

    // Read 2-byte length (little endian)
    if (offset + 2 >= data.size()) return;
    uint16_t length = data[offset + 1] | (data[offset + 2] << 8);

    // Bug: If length is 0, offset + 3 + 0 == offset + 3. But wait, if type is 0 and length is 0
    // let's make the bug more direct: length specifies total record length including header.
    // If length is 0 due to corruption, offset doesn't advance.

    // We will assume length is the payload length.
    // Total record size = 1 (type) + 2 (length) + payload_length.
    // BUG: If length is 0 and type is 0 (zero-padded corruption), it should be a bug.
    // Actually, let's inject a direct infinite recursion:

    if (length > data.size() - offset - 3) {
        // truncated
        return;
    }

    // A valid record
    if (type != 0) {
        std::string payload(data.begin() + offset + 3, data.begin() + offset + 3 + length);
        records.push_back({type, payload});
    }

    // Calculate next offset. If corruption caused length=0 and type=0, let's say the logic
    // incorrectly tries to re-parse the same block if it doesn't recognize it, or just 
    // fails to advance correctly.
    size_t next_offset = offset + 3 + length;

    if (type == 0 && length == 0) {
        // CORRUPTION: power loss wrote zeros.
        // Buggy logic: forgot to advance next_offset properly for type 0, or just recursively calls with same offset.
        next_offset = offset; // INFINITE RECURSION
    }

    parse_record(data, next_offset, records);
}
EOF

    cat << 'EOF' > /home/user/ticket_8492/main.cpp
#include "wal_parser.h"
#include <iostream>
#include <fstream>

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <wal_file>" << std::endl;
        return 1;
    }

    WalParser parser;
    std::vector<Record> records = parser.parse(argv[1]);

    std::ofstream out("recovered.txt");
    for (const auto& rec : records) {
        out << "Type: " << rec.type << " Payload: " << rec.payload << "\n";
    }
    out.close();

    std::cout << "Successfully recovered " << records.size() << " records." << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /tmp/generate_wal.py
import struct

with open('/home/user/ticket_8492/data.wal', 'wb') as f:
    # Valid record 1: Type 'A', length 4, payload "TEST"
    f.write(struct.pack('<B H 4s', ord('A'), 4, b'TEST'))
    # Valid record 2: Type 'B', length 2, payload "OK"
    f.write(struct.pack('<B H 2s', ord('B'), 2, b'OK'))
    # Corrupted record: Zeros
    f.write(b'\x00\x00\x00')
    f.write(b'\x00\x00\x00')
EOF

    python3 /tmp/generate_wal.py
    rm /tmp/generate_wal.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/ticket_8492
    chmod -R 777 /home/user
