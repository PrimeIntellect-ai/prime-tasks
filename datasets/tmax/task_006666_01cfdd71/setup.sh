#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake gcc g++ make
    pip3 install pytest

    mkdir -p /home/user/pipeline/vendor/include
    mkdir -p /home/user/pipeline/vendor/lib
    mkdir -p /home/user/pipeline/src

    cat << 'EOF' > /home/user/pipeline/vendor/include/mathops.h
#ifndef MATHOPS_H
#define MATHOPS_H
#ifdef __cplusplus
extern "C" {
#endif
int mathops_square(int x);
#ifdef __cplusplus
}
#endif
#endif
EOF

    cat << 'EOF' > /home/user/pipeline/vendor/lib/mathops.c
#include "../include/mathops.h"
int mathops_square(int x) {
    return x * x;
}
EOF

    gcc -shared -fPIC /home/user/pipeline/vendor/lib/mathops.c -o /home/user/pipeline/vendor/lib/libmathops.so

    cat << 'EOF' > /home/user/pipeline/src/vm.cpp
#include <vector>
#include <iostream>
#include "mathops.h"

extern "C" {
    int execute_vm(const int* bytecode) {
        std::vector<int> stack;
        int pc = 0;
        while (true) {
            int opcode = bytecode[pc++];
            if (opcode == 0) { // OP_END
                return stack.empty() ? 0 : stack.back();
            } else if (opcode == 1) { // OP_PUSH
                stack.push_back(bytecode[pc++]);
            } else if (opcode == 2) { // OP_ADD
                if (stack.size() < 2) return -1;
                int b = stack.back(); stack.pop_back();
                int a = stack.back(); stack.pop_back();
                stack.push_back(a + b);
            } else if (opcode == 3) { // OP_SQUARE
                if (stack.size() < 1) return -1;
                int a = stack.back(); stack.pop_back();
                stack.push_back(mathops_square(a));
            } else {
                return -1; // Unknown opcode
            }
        }
    }
}
EOF

    cat << 'EOF' > /home/user/pipeline/src/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(DataVM)

# BROKEN: Missing include directories and link libraries
add_library(vm SHARED vm.cpp)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
