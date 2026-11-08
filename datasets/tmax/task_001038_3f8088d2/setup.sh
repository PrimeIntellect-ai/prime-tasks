#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake gcc make espeak ffmpeg
    pip3 install pytest

    mkdir -p /home/user/dsp_server
    mkdir -p /app/deps
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create dummy libmongoose.so and mongoose.h
    echo "int mongoose_init() { return 0; }" > /tmp/mongoose.c
    gcc -shared -fPIC -o /app/deps/libmongoose.so /tmp/mongoose.c
    echo "int mongoose_init();" > /app/deps/mongoose.h

    # Create project files
    cat << 'EOF' > /home/user/dsp_server/main.c
#include <stdio.h>
#include "server.h"

int main() {
    start_server();
    return 0;
}
EOF

    cat << 'EOF' > /home/user/dsp_server/server.c
#include <stdio.h>
#include "server.h"

void start_server() {
    printf("Server started.\n");
}
EOF

    cat << 'EOF' > /home/user/dsp_server/server.h
#ifndef SERVER_H
#define SERVER_H

void start_server();

#endif
EOF

    cat << 'EOF' > /home/user/dsp_server/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(dsp_server)

add_executable(dsp_server main.c server.c)
target_link_libraries(dsp_server mongoose)
EOF

    # Generate voice note
    espeak -w /app/voicenote.wav "Hey, we need to secure the DSP emulator immediately. The validator needs to enforce three rules. First, absolutely reject any program that contains the halt opcode, which is zero x F F. Second, reject the sequence where opcode zero x 1 A is immediately followed by zero x 2 B, as that causes a memory leak. Third, any program strictly longer than 128 bytes is too large and must be rejected."

    # Create corpus files
    # Clean: len <= 128, no 0xFF, no 0x1A followed by 0x2B
    echo -n -e '\x01\x02\x03' > /app/corpus/clean/test1.bin
    echo -n -e '\x1A\x00\x2B' > /app/corpus/clean/test2.bin

    # Evil: contains 0xFF
    echo -n -e '\x01\xFF\x03' > /app/corpus/evil/test1.bin
    # Evil: contains 0x1A 0x2B
    echo -n -e '\x01\x1A\x2B\x03' > /app/corpus/evil/test2.bin
    # Evil: len > 128
    head -c 129 /dev/zero > /app/corpus/evil/test3.bin

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
