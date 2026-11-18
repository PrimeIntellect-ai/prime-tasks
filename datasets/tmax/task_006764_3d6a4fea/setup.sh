#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/workspace/inbox
    mkdir -p /home/user/workspace/organized

    for i in $(seq 1 10); do
        echo "data $i" > /home/user/workspace/inbox/dataset_${i}.dat
    done

    cat << 'EOF' > /home/user/workspace/expr.c
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

// Extremely basic evaluator for testing (only handles single '+' or '-')
// Format expected: "A+B" or "A-B" where A and B are integers
int evaluate_math(const char* expression, int* out_result) {
    if (!expression || !out_result) return -1;

    int a = 0, b = 0;
    char op = 0;
    const char* p = expression;

    while (*p && isspace(*p)) p++;
    while (*p && isdigit(*p)) { a = a * 10 + (*p - '0'); p++; }
    while (*p && isspace(*p)) p++;
    if (*p == '+' || *p == '-') { op = *p; p++; } else { return -1; }
    while (*p && isspace(*p)) p++;
    while (*p && isdigit(*p)) { b = b * 10 + (*p - '0'); p++; }

    if (op == '+') *out_result = a + b;
    else if (op == '-') *out_result = a - b;
    else return -1;

    return 0;
}
EOF

    cat << 'EOF' > /home/user/workspace/expr.h
#ifndef EXPR_H
#define EXPR_H
int evaluate_math(const char* expression, int* out_result);
#endif
EOF

    chmod -R 777 /home/user
