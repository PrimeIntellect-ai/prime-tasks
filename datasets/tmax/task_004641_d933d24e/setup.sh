#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ binutils strace gdb bsdmainutils
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/wal.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>

int main(int argc, char* argv[]) {
    if (argc != 3) return 1;
    std::ifstream in(argv[1], std::ios::binary);
    std::ofstream out(argv[2], std::ios::binary);
    if (!in || !out) return 1;

    out.write("WALC", 4);

    in.seekg(0, std::ios::end);
    std::streampos fsize = in.tellg();
    in.seekg(0, std::ios::beg);

    uint32_t size = (fsize < 0) ? 0 : static_cast<uint32_t>(fsize);

    if (size > 0) {
        std::vector<uint8_t> data(size);
        in.read(reinterpret_cast<char*>(data.data()), size);

        uint8_t current_byte = data[0];
        uint8_t count = 1;

        for (uint32_t i = 1; i < size; ++i) {
            if (data[i] == current_byte && count < 255) {
                count++;
            } else {
                out.put(count);
                out.put(current_byte);
                current_byte = data[i];
                count = 1;
            }
        }
        out.put(count);
        out.put(current_byte);
    }

    out.write(reinterpret_cast<const char*>(&size), 4);
    return 0;
}
EOF

g++ -O2 /tmp/wal.cpp -o /app/wal_archive_tool
strip /app/wal_archive_tool
chmod +x /app/wal_archive_tool
rm /tmp/wal.cpp

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
