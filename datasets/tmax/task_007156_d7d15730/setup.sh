#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gdb coreutils bash
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the configuration file
    echo "log_level=debug" > /home/user/conf

    # Create the vulnerable C++ source code
    cat << 'EOF' > /home/user/parser.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cstdlib>

int main(int argc, char* argv[]) {
    const char* conf_path = std::getenv("CONF_PATH");
    if (!conf_path) {
        std::cerr << "Fatal: Configuration missing." << std::endl;
        return 1;
    }

    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <payload>" << std::endl;
        return 1;
    }

    std::ifstream file(argv[1], std::ios::binary);
    if (!file) {
        std::cerr << "Failed to open file." << std::endl;
        return 1;
    }

    while (file && !file.eof()) {
        uint32_t chunk_size = 0;
        file.read(reinterpret_cast<char*>(&chunk_size), sizeof(chunk_size));

        if (file.gcount() < sizeof(chunk_size)) {
            break;
        }

        // BUG: If chunk_size is 0, the file pointer never advances, causing an infinite loop.
        // FIX: Add `if (chunk_size == 0) break;` or similar handling here.

        std::vector<char> buffer(chunk_size);
        file.read(buffer.data(), chunk_size);

        std::cout << "Processed chunk of size " << chunk_size << std::endl;
    }

    return 0;
}
EOF

    # Create the payload file
    python3 -c "import struct; f = open('/home/user/payload.dat', 'wb'); f.write(struct.pack('<I', 4) + b'AAAA' + struct.pack('<I', 0)); f.close()"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
