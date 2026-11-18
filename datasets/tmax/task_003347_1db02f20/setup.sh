#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cmake libtbb-dev binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_sorter_source.cpp
#include <iostream>
#include <vector>
#include <fstream>
#include <algorithm>
#include <cstring>
#include <cstdint>

#pragma pack(push, 1)
struct Record {
    uint64_t id;
    double score;
    char label[16];
};
#pragma pack(pop)

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::ifstream is(argv[1], std::ios::binary | std::ios::ate);
    if (!is) return 1;
    size_t size = is.tellg();
    is.seekg(0, std::ios::beg);
    std::vector<Record> records(size / sizeof(Record));
    if (!is.read(reinterpret_cast<char*>(records.data()), size)) return 1;

    std::sort(records.begin(), records.end(), [](const Record& a, const Record& b) {
        if (a.score != b.score) return a.score > b.score;
        int cmp = std::strncmp(a.label, b.label, 16);
        if (cmp != 0) return cmp < 0;
        return a.id < b.id;
    });

    std::cout.write(reinterpret_cast<const char*>(records.data()), size);
    return 0;
}
EOF

    g++ -O3 -std=c++17 /app/legacy_sorter_source.cpp -o /app/legacy_sorter
    strip --strip-all /app/legacy_sorter
    rm /app/legacy_sorter_source.cpp

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/workspace
    chmod -R 777 /home/user
