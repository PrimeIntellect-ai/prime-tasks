#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak g++ make

    # Install PyTorch CPU first to save time and space, then whisper
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu
    pip3 install pytest openai-whisper

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/spec_memo.wav "For the new encoding pipeline, the algorithm is as follows. First, take the input string and shift every character's ASCII value forward by three. If the character is not a printable ASCII character, leave it unchanged. But for printable characters, wrap around from tilde (ASCII 126) back to space (ASCII 32). So tilde becomes double quote. Second, compute the checksum by taking the sum of all the original unshifted characters' ASCII values, modulo 256. Finally, the output string should be the shifted string, followed by a pipe character, followed by the checksum formatted as exactly two lowercase hexadecimal digits."

    # Create the oracle C++ implementation
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <string>
#include <iomanip>
#include <sstream>

void encode_data(const char* input, char* output) {
    int sum = 0;
    std::string shifted = "";
    for(int i=0; input[i] != '\0'; ++i) {
        unsigned char c = input[i];
        sum = (sum + c) % 256;
        if (c >= 32 && c <= 126) {
            c = c + 3;
            if (c > 126) {
                c = 32 + (c - 127);
            }
        }
        shifted += c;
    }
    std::stringstream ss;
    ss << shifted << "|" << std::hex << std::setw(2) << std::setfill('0') << sum;
    std::string res = ss.str();
    for(size_t i=0; i<res.length(); ++i) output[i] = res[i];
    output[res.length()] = '\0';
}

int main() {
    std::string line;
    char out_buf[1024];
    while (std::getline(std::cin, line)) {
        encode_data(line.c_str(), out_buf);
        std::cout << out_buf << "\n";
    }
    return 0;
}
EOF

    g++ -O2 /tmp/oracle.cpp -o /app/oracle_encoder_cli
    rm /tmp/oracle.cpp

    # Create legacy project
    mkdir -p /app/legacy_project
    cat << 'EOF' > /app/legacy_project/main.cpp
#include <iostream>
#include "encoder.h"

int main() {
    char buf[1024];
    encode_data("test", buf);
    std::cout << buf << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /app/legacy_project/encoder.h
#ifndef ENCODER_H
#define ENCODER_H

void encode_data(const char* input, char* output);

#endif
EOF

    cat << 'EOF' > /app/legacy_project/encoder.cpp
#include "encoder.h"

void encode_data(const char* input, char* output) {
    // legacy broken implementation
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
