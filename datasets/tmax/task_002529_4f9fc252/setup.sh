#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake gcc valgrind
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project/src
    mkdir -p /home/user/project/build

    cat << 'EOF' > /home/user/project/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(SolverProject C)

set(CMAKE_C_STANDARD 99)

# Missing: RPATH settings so Python can load it easily
set(CMAKE_SKIP_BUILD_RPATH FALSE)
set(CMAKE_BUILD_WITH_RPATH TRUE)
set(CMAKE_INSTALL_RPATH "${CMAKE_CURRENT_BINARY_DIR}")

add_library(math_utils SHARED src/math_utils.c)
add_library(solver_core SHARED src/solver_core.c)

# BUG: missing target_link_libraries
EOF

    cat << 'EOF' > /home/user/project/src/math_utils.h
#ifndef MATH_UTILS_H
#define MATH_UTILS_H
int multiply_factor(int val);
#endif
EOF

    cat << 'EOF' > /home/user/project/src/math_utils.c
#include "math_utils.h"
int multiply_factor(int val) {
    return val * 10;
}
EOF

    cat << 'EOF' > /home/user/project/src/solver_core.c
#include <stdlib.h>
#include "math_utils.h"

int compute_score(int* items, int num_items) {
    int score = 0;
    // BUG: Buffer overflow (<= instead of <)
    // BUG: Memory leak (no free)
    int* cache = (int*)malloc(num_items * sizeof(int));

    for (int i = 0; i <= num_items; i++) {
        cache[i] = items[i] * (i + 1);
        score += multiply_factor(cache[i]);
    }

    return score;
}
EOF

    cat << 'EOF' > /home/user/project/wrapper.py
import ctypes
import os

# Load library
lib_path = os.path.join(os.path.dirname(__file__), "build", "libsolver_core.so")
solver = ctypes.CDLL(lib_path)

# configure ctypes argtypes/restype here...

def solve_coloring():
    # Write CSP here
    pass

if __name__ == "__main__":
    # Solve, call C function, write to /home/user/result.txt
    pass
EOF

    chmod -R 777 /home/user
