#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cmake cargo rustc
    pip3 install pytest websockets

    mkdir -p /home/user/libexpr
    cat << 'EOF' > /home/user/libexpr/expr.h
#ifndef EXPR_H
#define EXPR_H
int evaluate_expression(const char* input, int* result);
#endif
EOF

    cat << 'EOF' > /home/user/libexpr/expr.c
#include "expr.h"
#include <stdio.h>
#include <string.h>

int evaluate_expression(const char* input, int* result) {
    char op[4]; // BUG: Too small for safety if sscanf reads more
    int a, b;
    // VULNERABILITY: %s without width limit causes buffer overflow
    if (sscanf(input, "%s %d %d", op, &a, &b) != 3) {
        return -1;
    }

    if (strcmp(op, "ADD") == 0) {
        *result = a + b;
        return 0;
    } else if (strcmp(op, "SUB") == 0) {
        *result = a - b;
        return 0;
    } else if (strcmp(op, "MUL") == 0) {
        *result = a * b;
        return 0;
    }

    return -1;
}
EOF

    cat << 'EOF' > /home/user/libexpr/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(libexpr C)

add_library(expr SHARED expr.c)
# Missing INSTALL or proper RPATH setup, but the agent can fix it or use build.rs to link correctly.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
