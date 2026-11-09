#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        cmake \
        g++ \
        make \
        socat \
        netcat-openbsd \
        curl \
        jq \
        espeak \
        ffmpeg

    pip3 install pytest

    # Create directories
    mkdir -p /home/user/legacy_audio
    mkdir -p /app

    # Create C++ project files
    cat << 'EOF' > /home/user/legacy_audio/audio_hash.h
#pragma once
#include <string>

std::string compute_hash(const std::string& transcript, const std::string& seed);
EOF

    cat << 'EOF' > /home/user/legacy_audio/audio_hash.cpp
#include "audio_hash.h"
#include <string>

std::string compute_hash(const std::string& transcript, const std::string& seed) {
    // A simple dummy hash for demonstration
    return transcript + "_" + seed + "_hashed";
}
EOF

    cat << 'EOF' > /home/user/legacy_audio/main.cpp
#include <iostream>
#include "audio_hash.h"

int main(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <transcript> <seed>\n";
        return 1;
    }
    std::cout << compute_hash(argv[1], argv[2]) << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/legacy_audio/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(legacy_audio)

add_library(audio_hash SHARED audio_hash.cpp)
add_executable(hasher_cli main.cpp)
target_link_libraries(hasher_cli audio_hash)
EOF

    # Generate the voicemail audio file
    espeak -w /app/voicemail.wav "The migration seed phrase is rusted metal."

    # Create user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
