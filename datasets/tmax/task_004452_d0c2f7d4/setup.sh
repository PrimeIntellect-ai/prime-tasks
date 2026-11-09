#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        cmake \
        g++ \
        make \
        tesseract-ocr \
        nlohmann-json3-dev \
        python3-pil

    pip3 install pytest

    mkdir -p /app/src /app/lib /app/clean /app/evil /app/hidden_clean /app/hidden_evil

    # Create image using Python PIL
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'MIN_VERSION: 1.4.2-rc.1\nWS_PORT: 8080', fill=(0,0,0))
img.save('/app/deploy_info.png')
"

    # Create asm_checker.s
    cat << 'EOF' > /app/src/asm_checker.s
.global verify_magic
.type verify_magic, @function
verify_magic:
    mov %edi, %eax
    xor $0xCAFEBABE, %eax
    test %eax, %eax
    sete %al
    movzbl %al, %eax
    ret
EOF

    # Create CMakeLists.txt
    cat << 'EOF' > /app/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(ConfigFilter)
set(CMAKE_CXX_STANDARD 17)
add_executable(config_filter src/main.cpp)
# Missing target_link_libraries and link directories
EOF

    # Create main.cpp
    cat << 'EOF' > /app/src/main.cpp
#include <iostream>
#include <fstream>
#include <string>

extern "C" int verify_magic(int magic);

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    // Implement JSON parsing, semver comparison, and validation here
    return 1;
}
EOF

    # Create test configs
    cat << 'EOF' > /app/clean/config1.json
{"version": "1.4.2-rc.1", "ws_endpoint": "ws://secure.local:8080", "magic_code": 3405691582}
EOF

    cat << 'EOF' > /app/evil/config1.json
{"version": "1.4.1", "ws_endpoint": "ws://secure.local:8080", "magic_code": 3405691582}
EOF

    cat << 'EOF' > /app/hidden_clean/config1.json
{"version": "1.5.0", "ws_endpoint": "ws://secure.local:8080", "magic_code": 3405691582}
EOF

    cat << 'EOF' > /app/hidden_evil/config1.json
{"version": "1.5.0", "ws_endpoint": "ws://secure.local:8081", "magic_code": 3405691582}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
