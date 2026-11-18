#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    # Create directories
    mkdir -p /app/liblogpack-1.2
    mkdir -p /opt/oracle

    # Create liblogpack source files
    cat << 'EOF' > /app/liblogpack-1.2/logpack.h
#ifndef LOGPACK_H
#define LOGPACK_H
#include <cstddef>
void pack_data(const unsigned char* in, size_t in_len, unsigned char* out, size_t* out_len);
#endif
EOF

    cat << 'EOF' > /app/liblogpack-1.2/logpack.cpp
#include "logpack.h"

void pack_data(const unsigned char* in, size_t in_len, unsigned char* out, size_t* out_len) {
    for (size_t i = 0; i < in_len; ++i) {
        out[i] = in[i] ^ 0x5A; // Simple XOR compression
    }
    *out_len = in_len;
}
EOF

    # Create Makefile with deliberate typo
    cat << 'EOF' > /app/liblogpack-1.2/Makefile
CXX = g++ -m32
CXXFLAGS = -O2 -Wall

all: liblogpack.a

liblogpack.a: logpack.o
	ar rcs liblogpack.a logpack.o

logpack.o: logpack.cpp logpack.h
	$(CXX) $(CXXFLAGS) -c logpack.cpp

clean:
	rm -f *.o *.a
EOF

    # Create and compile oracle
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <string>
#include <vector>
#include <cstdint>
#include <cstring>
#include <algorithm>

void pack_data_oracle(const unsigned char* in, size_t in_len, unsigned char* out, size_t* out_len) {
    for (size_t i = 0; i < in_len; ++i) {
        out[i] = in[i] ^ 0x5A;
    }
    *out_len = in_len;
}

int main() {
    std::string hex_str;
    if (!(std::cin >> hex_str)) return 0;

    std::vector<unsigned char> bin_data;
    for (size_t i = 0; i < hex_str.length(); i += 2) {
        std::string byteString = hex_str.substr(i, 2);
        unsigned char byte = (unsigned char) strtol(byteString.c_str(), NULL, 16);
        bin_data.push_back(byte);
    }

    std::cout.write("PACKv1\0\0", 8);

    size_t offset = 0;
    while (offset < bin_data.size()) {
        size_t chunk_size = std::min((size_t)4096, bin_data.size() - offset);
        unsigned char out_buf[8192 + 16];
        size_t out_len = 0;
        pack_data_oracle(bin_data.data() + offset, chunk_size, out_buf, &out_len);

        uint16_t uncomp_size = chunk_size;
        uint16_t comp_size = out_len;
        std::cout.write((char*)&uncomp_size, 2);
        std::cout.write((char*)&comp_size, 2);
        std::cout.write((char*)out_buf, out_len);

        offset += chunk_size;
    }
    return 0;
}
EOF

    g++ -O2 /tmp/oracle.cpp -o /opt/oracle/archiver_oracle
    rm /tmp/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
