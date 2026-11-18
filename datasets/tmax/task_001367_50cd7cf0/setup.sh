#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    # Create directories
    mkdir -p /app/zres_lib-1.2.0
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create Makefile
    cat << 'EOF' > /app/zres_lib-1.2.0/Makefile
CXX = g++
CXXFLAGS = -O2

libzres.a: zres.o
	ar rcs libzres.a zres.o

zres.o: zres.cpp zres.h
	$(CXX) $(CXXFLAGS) -c zres.cpp -o zres.o

clean:
	rm -f *.o *.a
EOF

    # Create zres.h
    cat << 'EOF' > /app/zres_lib-1.2.0/zres.h
#ifndef ZRES_H
#define ZRES_H
#include <string>

void extract_archive(const std::string& archive_path, const std::string& output_dir);

#endif
EOF

    # Create zres.cpp
    cat << 'EOF' > /app/zres_lib-1.2.0/zres.cpp
#include "zres.h"
#include <fstream>
#include <iostream>
#include <filesystem>
#include <stdexcept>
#include <vector>

void extract_archive(const std::string& archive_path, const std::string& output_dir) {
    std::ifstream in(archive_path, std::ios::binary);
    if (!in) throw std::runtime_error("Cannot open archive");

    uint32_t num_files = 0;
    if (!in.read(reinterpret_cast<char*>(&num_files), sizeof(num_files))) return;

    for (uint32_t i = 0; i < num_files; ++i) {
        uint32_t name_len = 0;
        in.read(reinterpret_cast<char*>(&name_len), sizeof(name_len));
        std::string file_name_from_archive(name_len, '\0');
        in.read(&file_name_from_archive[0], name_len);

        uint32_t data_len = 0;
        in.read(reinterpret_cast<char*>(&data_len), sizeof(data_len));
        std::vector<char> data(data_len);
        in.read(data.data(), data_len);

        // Vulnerable path construction
        std::string dest_path = output_dir + "/" + file_name_from_archive;

        std::ofstream out(dest_path, std::ios::binary);
        if (out) {
            out.write(data.data(), data_len);
        }
    }
}
EOF

    # Generate corpora using python
    cat << 'EOF' > /tmp/gen_zres.py
import struct

def make_zres(path, files):
    with open(path, 'wb') as f:
        f.write(struct.pack('<I', len(files)))
        for name, data in files:
            name_b = name.encode('utf-8')
            f.write(struct.pack('<I', len(name_b)))
            f.write(name_b)
            f.write(struct.pack('<I', len(data)))
            f.write(data)

make_zres('/app/corpora/clean/dataset1.zres', [
    ('data_1.bin', b'AAA'),
    ('data_2.bin', b'BBB'),
    ('metadata.log', b'OriginalName: data_1.bin\nNewName: sensor_alpha_01.bin\n---\nOriginalName: data_2.bin\nNewName: sensor_beta_02.bin\n---\n')
])

make_zres('/app/corpora/evil/exploit1.zres', [
    ('../hacked.txt', b'EVIL'),
    ('metadata.log', b'OriginalName: data_1.bin\nNewName: sensor_alpha_01.bin\n---\n')
])

make_zres('/app/corpora/evil/exploit2.zres', [
    ('/etc/hacked.txt', b'EVIL'),
    ('metadata.log', b'OriginalName: data_1.bin\nNewName: sensor_alpha_01.bin\n---\n')
])
EOF
    python3 /tmp/gen_zres.py
    rm /tmp/gen_zres.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
