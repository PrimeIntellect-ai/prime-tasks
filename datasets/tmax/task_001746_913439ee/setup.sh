#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake build-essential nginx curl
    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /home/user/project/lib
    mkdir -p /home/user/project/src
    mkdir -p /home/user/evaluator
    mkdir -p /tmp/nginx

    # Root CMakeLists.txt
    cat << 'EOF' > /home/user/project/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(CI_Build_Project)

add_subdirectory(lib)
add_subdirectory(src)
EOF

    # Lib CMakeLists.txt
    cat << 'EOF' > /home/user/project/lib/CMakeLists.txt
add_library(custom_math SHARED custom_math.cpp)
target_include_directories(custom_math PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
EOF

    # Lib source and header
    cat << 'EOF' > /home/user/project/lib/custom_math.h
#ifndef CUSTOM_MATH_H
#define CUSTOM_MATH_H
int multiply(int a, int b);
#endif
EOF

    cat << 'EOF' > /home/user/project/lib/custom_math.cpp
#include "custom_math.h"
int multiply(int a, int b) {
    return a * b;
}
EOF

    # Src CMakeLists.txt (INTENTIONALLY BROKEN)
    cat << 'EOF' > /home/user/project/src/CMakeLists.txt
add_executable(app main.cpp)
# Missing library linking here
EOF

    # Src main
    cat << 'EOF' > /home/user/project/src/main.cpp
#include <iostream>
#include "custom_math.h"

int main() {
    std::cout << "Pipeline success. 5 * 6 = " << multiply(5, 6) << std::endl;
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /tmp/nginx
