#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/libcalc.c
#include <stdio.h>
int parse_op(int a, int b) {
    // Dummy function that conflicts
    return a * b + 100; 
}
EOF
    gcc -shared -o /home/user/project/libcalc.so -fPIC /home/user/project/libcalc.c

    cat << 'EOF' > /home/user/project/expr_eval.c
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// BUG 2: This symbol conflicts with libcalc.so. Should be static or renamed.
int parse_op(char op, int a, int b) {
    switch(op) {
        case '+': return a + b;
        case '-': return a - b;
        case '*': return a * b;
        case '/': return b != 0 ? a / b : 0;
        default: return 0;
    }
}

// Parses expressions of the form "A+B"
int* evaluate_expressions(char** exprs, int count) {
    // BUG 1: Allocates 'count' bytes instead of 'count * sizeof(int)'
    int* results = (int*)malloc(count); 

    for (int i = 0; i < count; i++) {
        int a, b;
        char op;
        if (sscanf(exprs[i], "%d%c%d", &a, &op, &b) == 3) {
            results[i] = parse_op(op, a, b);
        } else {
            results[i] = 0;
        }
    }
    return results;
}

void free_results(int* results) {
    free(results);
}
EOF

    cat << 'EOF' > /home/user/project/input.txt
10+5
20-3
4*4
18/2
EOF

    cat << 'EOF' > /home/user/project/baseline.txt
9
15
16
20
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
