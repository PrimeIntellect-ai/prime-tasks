#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make cmake
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline/vendor/lib
    mkdir -p /home/user/pipeline/vendor/src
    mkdir -p /home/user/pipeline/src
    mkdir -p /home/user/pipeline/include

    cat << 'EOF' > /home/user/pipeline/vendor/src/device_proto.c
int get_proto_version() { return 2; }
EOF
    gcc -shared -fPIC -o /home/user/pipeline/vendor/lib/libdevice_proto.so /home/user/pipeline/vendor/src/device_proto.c

    cat << 'EOF' > /home/user/pipeline/src/parser.c
#include "parser.h"
int parse_device_state(int event) {
    static int state = 0;
    if (state == 0 && event == 1) { state = 1; return state; }
    if (state == 1 && event == 2) { state = 2; return state; }
    if (state == 2 && event == 3) { state = -1; return state; }
    return -1;
}
EOF

    cat << 'EOF' > /home/user/pipeline/include/parser.h
#ifndef PARSER_H
#define PARSER_H
int parse_device_state(int event);
#endif
EOF

    cat << 'EOF' > /home/user/pipeline/src/main.c
#include <stdio.h>
#include "parser.h"

extern int get_proto_version();

int main() {
    if (get_proto_version() != 2) {
        printf("BAD PROTO\n");
        return 1;
    }
    parse_device_state(1);
    parse_device_state(2);
    if (parse_device_state(3) == 3) {
        printf("SUCCESS\n");
        return 0;
    }
    printf("FAILED\n");
    return 1;
}
EOF

    cat << 'EOF' > /home/user/pipeline/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(MobilePipeline C)

add_executable(mobile_test src/main.c src/parser.c)
target_include_directories(mobile_test PRIVATE include)

# BUG: Missing target_link_directories or find_library for vendor/lib
target_link_libraries(mobile_test device_proto)
EOF

    chown -R user:user /home/user/pipeline
    chmod -R 777 /home/user
