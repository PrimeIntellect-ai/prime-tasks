#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg git g++ make
    pip3 install pytest

    mkdir -p /app/logs

    # Create dummy video
    ffmpeg -f lavfi -i testsrc=duration=10:size=320x240:rate=30 -c:v libx264 -pix_fmt yuv420p /app/incident-stream.mp4

    # Create container logs
    cat << 'EOF' > /app/logs/container.log
[INFO] Starting video processing service
[INFO] Processing frame 141... OK
[INFO] Processing frame 142... OK
[INFO] Processing frame 143...
Segmentation fault (core dumped)
EOF

    # Setup git repo
    mkdir -p /home/user/video_service
    cd /home/user/video_service
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    # Safe version
    cat << 'EOF' > processor.cpp
#include <iostream>
#include <fstream>
#include <vector>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::ifstream file(argv[1], std::ios::binary);
    std::vector<unsigned char> data((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());

    for (size_t i = 0; i < data.size(); ++i) {
        data[i] = 255 - data[i];
    }

    std::cout.write(reinterpret_cast<const char*>(data.data()), data.size());
    return 0;
}
EOF
    git add processor.cpp
    git commit -m "Initial commit"
    git tag v1.0.0

    # Compile oracle
    g++ -O2 processor.cpp -o /app/oracle_bin

    # Bad version
    cat << 'EOF' > processor.cpp
#include <iostream>
#include <fstream>
#include <vector>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::ifstream file(argv[1], std::ios::binary);
    std::vector<unsigned char> data((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());

    size_t i = 0;
    for (; i + 16 <= data.size(); i += 16) {
        for (int j = 0; j < 16; ++j) {
            data[i+j] = 255 - data[i+j];
        }
    }

    // Bug: <= instead of <
    for (; i <= data.size(); ++i) {
        data[i] = 255 - data[i];
    }

    std::cout.write(reinterpret_cast<const char*>(data.data()), data.size());
    return 0;
}
EOF
    git add processor.cpp
    git commit -m "Optimize convolution loop using SIMD-like chunking"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
