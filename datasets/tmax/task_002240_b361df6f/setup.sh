#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/db_recovery
    cd /home/user/db_recovery

    # Create Makefile
    cat << 'EOF' > Makefile
all: recover
recover: recover.cpp
	g++ -O0 -g -std=c++11 recover.cpp -o recover
clean:
	rm -f recover
EOF

    # Create buggy recover.cpp
    cat << 'EOF' > recover.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <cstdint>
#include <cstring>

struct Record {
    uint16_t key_len;
    std::string key;
    uint32_t val_len;
    std::string val;
};

int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <wal_file>\n";
        return 1;
    }

    std::ifstream file(argv[1], std::ios::binary);
    if (!file) {
        std::cerr << "Failed to open file\n";
        return 1;
    }

    char magic[4];
    file.read(magic, 4);
    if (std::strncmp(magic, "WAL1", 4) != 0) {
        std::cerr << "Invalid WAL magic\n";
        return 1;
    }

    while (file.peek() != EOF) {
        uint16_t key_len;
        if (!file.read(reinterpret_cast<char*>(&key_len), sizeof(key_len))) break;

        char* key_buf = new char[key_len];
        file.read(key_buf, key_len);

        uint32_t val_len;
        file.read(reinterpret_cast<char*>(&val_len), sizeof(val_len));

        char* val_buf = new char[val_len];
        file.read(val_buf, val_len);

        // BUG: Constructing string without length causes read past buffer bounds looking for \0
        std::string key(key_buf); 
        std::string val(val_buf);

        std::cout << key << "=" << val << "\n";

        delete[] key_buf;
        delete[] val_buf;
    }

    return 0;
}
EOF

    # Python script to generate the WAL
    cat << 'EOF' > generate_wal.py
import struct

def write_record(f, key, val):
    kb = key.encode('utf-8')
    vb = val.encode('utf-8')
    f.write(struct.pack('<H', len(kb)))
    f.write(kb)
    f.write(struct.pack('<I', len(vb)))
    f.write(vb)

with open('system_state.wal', 'wb') as f:
    f.write(b'WAL1')
    write_record(f, 'active_connections', '1042')
    write_record(f, 'request_rate', '500')
    write_record(f, 'cpu_load_avg', '3.14')
    # Add a specific record that fills with A's to guarantee no null terminator nearby
    # and a long string to trigger segfault in the C++ string constructor
    kb = b'memory_usage_bytes'
    vb = b'9' * 1000
    f.write(struct.pack('<H', len(kb)))
    f.write(kb)
    f.write(struct.pack('<I', len(vb)))
    f.write(vb)
    write_record(f, 'uptime_seconds', '86400')
EOF

    python3 generate_wal.py
    rm generate_wal.py
    chown -R user:user /home/user/db_recovery

    chmod -R 777 /home/user
