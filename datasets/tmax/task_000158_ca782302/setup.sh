#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake g++ make jq
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/audioproc/src

    # Generate telemetry.wav using Python
    python3 -c "
import wave
with wave.open('/app/telemetry.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(44100)
    w.writeframes(b'\x00' * (44100 * 600 * 2))
"

    # Create CMakeLists.txt
    cat << 'EOF' > /home/user/audioproc/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(audioproc)
set(CMAKE_CXX_STANDARD 17)
add_executable(audioproc src/main.cpp src/processor.cpp)
EOF

    # Create processor.h
    cat << 'EOF' > /home/user/audioproc/src/processor.h
#pragma once
#include <vector>
#include <string>

struct Chunk {
    int id;
    double rms;
};

class AudioProcessor {
public:
    AudioProcessor();
    ~AudioProcessor();
    std::vector<Chunk>* process(const std::string& filepath);
};
EOF

    # Create processor.cpp
    cat << 'EOF' > /home/user/audioproc/src/processor.cpp
#include "processor.h"
#include <fstream>
#include <cmath>
#include <iostream>
#include <thread>
#include <chrono>

AudioProcessor::AudioProcessor() {}
AudioProcessor::~AudioProcessor() {}

std::vector<Chunk>* AudioProcessor::process(const std::string& filepath) {
    std::vector<Chunk>* results = new std::vector<Chunk>();

    // Sequential processing simulation
    for (int i = 0; i < 100; ++i) {
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
        Chunk c;
        c.id = i;
        c.rms = 0.05 + (i * 0.001);
        results->push_back(c);
    }

    return results;
}
EOF

    # Create main.cpp
    cat << 'EOF' > /home/user/audioproc/src/main.cpp
#include "processor.h"
#include <iostream>
#include <fstream>
#include <vector>

int main(int argc, char** argv) {
    if (argc < 3) return 1;
    std::string input = argv[1];
    std::string output = argv[2];

    AudioProcessor proc;
    std::vector<Chunk>* chunks = proc.process(input);

    std::ofstream out(output);
    out << "{\"file\": \"" << input << "\", \"chunks\": [";
    for (size_t i = 0; i < chunks->size(); ++i) {
        out << "{\"id\": " << (*chunks)[i].id << ", \"rms\": " << (*chunks)[i].rms << "}";
        if (i < chunks->size() - 1) out << ", ";
    }
    out << "]}" << std::endl;

    // Intentional memory leak
    // delete chunks;

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
