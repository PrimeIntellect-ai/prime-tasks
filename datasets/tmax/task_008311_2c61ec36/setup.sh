#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cmake gcc make
pip3 install pytest

mkdir -p /home/user/matheval/src /home/user/matheval/tests /home/user/matheval/build

cat << 'EOF' > /home/user/matheval/src/eval.h
#ifndef EVAL_H
#define EVAL_H
double eval_rpn(const char* expr);
#endif
EOF

cat << 'EOF' > /home/user/matheval/src/eval.c
#include "eval.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

double eval_rpn(const char* expr) {
    double stack[100];
    int top = -1;
    char buffer[256];
    strncpy(buffer, expr, 255);
    buffer[255] = '\0';

    char *token = strtok(buffer, " ");
    while (token != NULL) {
        if (isdigit(token[0]) || (token[0] == '-' && isdigit(token[1]))) {
            stack[++top] = atof(token);
        } else {
            if (top < 1) return 0.0; // Error
            double val1 = stack[top--];
            double val2 = stack[top--];

            // BUG: val1 and val2 are reversed for subtraction and division
            if (token[0] == '+') stack[++top] = val2 + val1;
            else if (token[0] == '-') stack[++top] = val1 - val2;
            else if (token[0] == '*') stack[++top] = val2 * val1;
            else if (token[0] == '/') stack[++top] = val1 / val2;
        }
        token = strtok(NULL, " ");
    }
    return stack[top];
}
EOF

cat << 'EOF' > /home/user/matheval/tests/test_eval.c
#include "../src/eval.h"
#include <stdio.h>
#include <math.h>

int main() {
    double res1 = eval_rpn("10 2 /");
    if (fabs(res1 - 5.0) > 0.001) {
        printf("Test 1 Failed: Expected 5.0, got %f\n", res1);
        return 1;
    }

    double res2 = eval_rpn("4 9 -");
    if (fabs(res2 - (-5.0)) > 0.001) {
        printf("Test 2 Failed: Expected -5.0, got %f\n", res2);
        return 1;
    }

    printf("All tests passed.\n");
    return 0;
}
EOF

cat << 'EOF' > /home/user/matheval/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(MathEval C)

set(CMAKE_SKIP_BUILD_RPATH TRUE)

add_library(matheval SHARED src/eval.c)

add_executable(test_eval tests/test_eval.c)
# BUG: link library typo (matheval_lib instead of matheval)
target_link_libraries(test_eval matheval_lib)

enable_testing()
add_test(NAME TestEval COMMAND test_eval)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
