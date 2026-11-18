#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cmake binutils
    pip3 install pytest

    mkdir -p /home/user/pr_review/build
    cd /home/user/pr_review

    cat << 'EOF' > mathops.c
int fast_compute(int a, int b) {
    return (a * b) ^ (a + b);
}
EOF

    cat << 'EOF' > baseline.py
def baseline_compute(a, b):
    return (a * b) ^ (a + b)
EOF

    cat << 'EOF' > bench.c
#include <stdio.h>

// TODO: Implement baseline_compute from baseline.py
int baseline_compute(int a, int b) {
    return 0; // REPLACEME
}

extern int fast_compute(int a, int b);

int main() {
    int a = 1234;
    int b = 5678;
    int res1 = baseline_compute(a, b);
    int res2 = fast_compute(a, b);

    if (res1 == res2) {
        printf("SUCCESS: %d\n", res1);
    } else {
        printf("FAIL: %d != %d\n", res1, res2);
    }
    return 0;
}
EOF

    cat << 'EOF' > CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(pr_review)

add_library(mathops SHARED mathops.c)
add_executable(bench bench.c)
# Linker configuration is missing here
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
