#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr g++ openssh-server openssh-client imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Generate legacy config image
    convert -size 400x100 xc:black -font DejaVu-Sans -pointsize 16 -fill white -draw "text 10,50 'CRITICAL PARAMS: XOR_KEY=42, MOD_FACTOR=15'" /app/legacy_config.png

    # Create and compile oracle binary
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <string>
int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    std::string input = argv[1];
    for (size_t i = 0; i < input.length(); ++i) {
        int val = (static_cast<int>(input[i]) ^ 42) + 15;
        std::cout << val << (i == input.length() - 1 ? "" : " ");
    }
    std::cout << std::endl;
    return 0;
}
EOF
    g++ /app/oracle.cpp -o /app/oracle_bin
    rm /app/oracle.cpp
    chmod +x /app/oracle_bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
