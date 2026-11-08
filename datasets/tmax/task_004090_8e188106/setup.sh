#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ zip unzip espeak gdb strace binutils
    pip3 install pytest

    mkdir -p /app/.hidden

    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <string>
#include <iomanip>

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    std::string input = argv[1];
    for (size_t i = 0; i < input.length(); ++i) {
        unsigned char c = (static_cast<unsigned char>(input[i]) ^ 0x5A) + i;
        std::cout << std::hex << std::setw(2) << std::setfill('0') << (int)c;
    }
    std::cout << std::endl;
    return 0;
}
EOF

    g++ -O2 -s /tmp/oracle.cpp -o /app/.hidden/payload_decoder_oracle
    cp /app/.hidden/payload_decoder_oracle /tmp/payload_decoder
    echo "dummy core dump" > /tmp/core.payload

    zip -P midnightshadow -j /app/evidence.zip /tmp/payload_decoder /tmp/core.payload

    espeak -w /app/intercepted_audio.wav "The access code is midnight shadow"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
