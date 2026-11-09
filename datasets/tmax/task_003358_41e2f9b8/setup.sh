#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake g++ make
    pip3 install pytest

    mkdir -p /home/user/project/src
    mkdir -p /home/user/project/include
    mkdir -p /home/user/project/test
    mkdir -p /home/user/project/build

    cat << 'EOF' > /home/user/project/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(MathLib)

set(CMAKE_CXX_STANDARD 17)

include_directories(include)

add_library(math_lib SHARED src/math_lib.cpp)

add_executable(test_app test/test_app.cpp)
EOF

    cat << 'EOF' > /home/user/project/include/math_lib.h
#ifndef MATH_LIB_H
#define MATH_LIB_H

struct FixedVector {
    int data[5];
    int size() const { return 5; }
    int sum() const;
};

void solve_constraint(FixedVector& v, int target_sum);

#endif
EOF

    cat << 'EOF' > /home/user/project/src/math_lib.cpp
#include "math_lib.h"

int FixedVector::sum() const {
    int s = 0;
    for (int i = 0; i < size(); ++i) {
        s += data[i];
    }
    return s;
}

void solve_constraint(FixedVector& v, int target_sum) {
    int current_sum = v.sum();
    int diff = target_sum - current_sum;

    // BUG: <= size() instead of < size()
    for (int i = 0; i <= v.size(); ++i) {
        if (diff == 0) break;
        int adjustment = diff > 0 ? 1 : -1;

        // Ensure non-negative
        if (v.data[i] + adjustment >= 0) {
            v.data[i] += adjustment;
            diff -= adjustment;
        }

        // Loop around if we still have diff to distribute
        if (i == v.size() - 1 && diff != 0) {
            i = -1; // will become 0 on ++i
        }
    }
}
EOF

    cat << 'EOF' > /home/user/project/test/test_app.cpp
#include <iostream>
#include <fstream>
#include <cstdlib>
#include "math_lib.h"

int main() {
    // Basic test
    FixedVector v = {10, 10, 10, 10, 10};
    solve_constraint(v, 100);

    if (v.sum() != 100) {
        std::cerr << "Basic test failed!" << std::endl;
        return 1;
    }

    // TODO: Add property-based test and write to /home/user/project/test_result.log

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
