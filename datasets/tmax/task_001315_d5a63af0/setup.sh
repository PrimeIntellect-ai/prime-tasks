#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git build-essential cmake valgrind nginx curl apache2-utils
    pip3 install pytest

    # Setup workspace and files
    mkdir -p /home/user/workspace/audio_service

    cat << 'EOF' > /home/user/workspace/audio_service/AudioChunkPool.cpp
#include <iostream>
#include <vector>

class AudioChunkPool {
public:
    AudioChunkPool() {}
    ~AudioChunkPool() {}
    // Intentionally buggy code here for the agent to fix
    void allocate() {
        int* leak = new int[100];
    }
};
EOF

    cat << 'EOF' > /home/user/workspace/audio_service/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(audio_service)
set(CMAKE_CXX_STANDARD 17)

# Dummy CMakeLists
add_executable(audio_service main.cpp AudioChunkPool.cpp)
EOF

    cat << 'EOF' > /home/user/workspace/audio_service/main.cpp
#include <iostream>
int main() {
    std::cout << "Listening on 127.0.0.1:9090" << std::endl;
    return 0;
}
EOF

    # Setup whisper.cpp (clone and build)
    git clone https://github.com/ggerganov/whisper.cpp.git /opt/whisper.cpp
    cd /opt/whisper.cpp
    cmake -B build
    cmake --build build --config Release

    # Setup audio fixture
    mkdir -p /app
    touch /app/build_audio_test.wav

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
