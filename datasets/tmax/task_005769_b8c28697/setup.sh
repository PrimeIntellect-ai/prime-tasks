#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake g++ make
    pip3 install pytest

    mkdir -p /home/user/tester/lib
    mkdir -p /home/user/tester/include
    mkdir -p /home/user/tester/src

    # Create the library source
    cat << 'EOF' > /home/user/tester/lib/metric.cpp
#include "../include/metric.h"
int initialize_metrics() {
    return 42;
}
EOF

    # Create the header
    cat << 'EOF' > /home/user/tester/include/metric.h
#ifndef METRIC_H
#define METRIC_H
int initialize_metrics();
#endif
EOF

    # Compile the shared library
    cd /home/user/tester/lib
    g++ -shared -fPIC metric.cpp -o libmetric.so
    rm metric.cpp

    # Create the broken CMakeLists.txt
    cat << 'EOF' > /home/user/tester/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(ApiTester)

set(CMAKE_CXX_STANDARD 17)

include_directories(${CMAKE_SOURCE_DIR}/include)

add_executable(analyzer src/analyzer.cpp)

# BUG: Missing link_directories or proper target_link_libraries path
target_link_libraries(analyzer metric)
EOF

    # Create the analyzer skeleton
    cat << 'EOF' > /home/user/tester/src/analyzer.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include "metric.h"

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    std::string url = argv[1];

    // TODO: Parse URL, calculate pairs, multiply by initialize_metrics(), and write to /home/user/tester/result.txt

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/tester
    chmod -R 777 /home/user
