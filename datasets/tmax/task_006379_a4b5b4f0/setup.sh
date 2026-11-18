#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev valgrind
    pip3 install pytest

    mkdir -p /home/user/pr-review

    cat << 'EOF' > /home/user/pr-review/evaluate.c
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Evaluates a simple addition expression like "10.5+2.0"
double eval_expr(const char* expr) {
    char* expr_copy = strdup(expr);
    char* plus_pos = strchr(expr_copy, '+');
    if (!plus_pos) {
        free(expr_copy);
        return 0.0;
    }
    *plus_pos = '\0';
    double left = atof(expr_copy);
    double right = atof(plus_pos + 1);

    // BUG: Memory leak here, expr_copy is not freed.
    // Agent must add: free(expr_copy);
    return left + right;
}
EOF

    cat << 'EOF' > /home/user/pr-review/check_constraints.py
import ctypes
import sys
import os

if len(sys.argv) != 2:
    print("Usage: python3 check_constraints.py <data_file>")
    sys.exit(1)

lib = ctypes.CDLL('/home/user/pr-review/libeval.so')

# AGENT MUST ADD:
# lib.eval_expr.restype = ctypes.c_double
# lib.eval_expr.argtypes = [ctypes.c_char_p]

with open(sys.argv[1], 'r') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        expr, threshold_str = line.split(',')
        threshold = float(threshold_str)

        # Call C library
        result = lib.eval_expr(expr.encode('utf-8'))

        # Constraint check
        if result >= threshold:
            print(f"{expr} == {result} >= {threshold}")
EOF

    cat << 'EOF' > /home/user/pr-review/data.txt
5.5+4.5,9.0
1.2+2.3,5.0
10.0+10.0,25.0
7.1+3.2,10.0
0.5+0.5,2.0
EOF

    # Compile the initial broken library
    gcc -shared -o /home/user/pr-review/libeval.so -fPIC /home/user/pr-review/evaluate.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
