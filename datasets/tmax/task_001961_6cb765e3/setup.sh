#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /app/generate_corpus.py
import struct
import os

def write_xar2(path, entries):
    with open(path, 'wb') as f:
        f.write(b'XAR2')
        f.write(struct.pack('<I', len(entries)))
        for entry in entries:
            etype, epath, edata = entry
            f.write(struct.pack('<B', etype))
            epath_b = epath.encode('ascii')
            f.write(struct.pack('<H', len(epath_b)))
            f.write(epath_b)
            if etype == 2: # dir
                f.write(struct.pack('<Q', 0))
            elif etype == 1: # symlink
                edata_b = edata.encode('ascii')
                f.write(struct.pack('<Q', len(edata_b)))
                f.write(edata_b)
            else: # file
                f.write(struct.pack('<Q', len(edata)))
                f.write(edata)

# Clean
write_xar2('/app/corpus/clean/clean1.xar2', [
    (0, 'hello.txt', b'hello world'),
    (2, 'dir', b''),
    (1, 'dir/link', 'hello.txt')
])

# Evil
write_xar2('/app/corpus/evil/absolute_path.xar2', [
    (0, '/etc/passwd', b'root')
])
write_xar2('/app/corpus/evil/dir_traversal.xar2', [
    (0, 'folder/../../etc/passwd', b'root')
])
write_xar2('/app/corpus/evil/symlink_escape.xar2', [
    (1, 'link', '../../etc/passwd')
])
write_xar2('/app/corpus/evil/symlink_loop.xar2', [
    (1, 'a', 'b'),
    (1, 'b', 'a')
])
write_xar2('/app/corpus/evil/symlink_chain.xar2', [
    (1, 'l1', 'l2'),
    (1, 'l2', 'l3'),
    (1, 'l3', 'l4'),
    (1, 'l4', 'l5'),
    (1, 'l5', 'l6'),
    (1, 'l6', 'target')
])
EOF

    python3 /app/generate_corpus.py

    cat << 'EOF' > /app/xar_tool.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cstring>
#include <cstdint>

using namespace std;

int main(int argc, char** argv) {
    if (argc < 3) return 1;
    string cmd = argv[1];
    string archive = argv[2];
    if (cmd == "create") {
        ofstream out(archive, ios::binary);
        out.write("XAR2", 4);
        uint32_t count = argc - 3;
        out.write((char*)&count, 4);
        for(int i=3; i<argc; i++) {
            uint8_t type = 0;
            out.write((char*)&type, 1);
            string path = argv[i];
            uint16_t plen = path.length();
            out.write((char*)&plen, 2);
            out.write(path.c_str(), plen);
            uint64_t dlen = 4;
            out.write((char*)&dlen, 8);
            out.write("data", 4);
        }
    }
    return 0;
}
EOF

    g++ /app/xar_tool.cpp -o /app/xar_tool
    strip /app/xar_tool
    rm /app/xar_tool.cpp /app/generate_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
