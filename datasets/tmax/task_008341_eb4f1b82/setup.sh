#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/evaluator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

double evaluate_postfix(const char* expr) {
    char* token;
    // BUG 1: Missing +1 for null terminator
    char* expr_copy = malloc(strlen(expr)); 
    strcpy(expr_copy, expr);

    double stack[100];
    int top = -1;

    token = strtok(expr_copy, " ");
    while (token != NULL) {
        if (token[0] == '+') {
            stack[top-1] = stack[top-1] + stack[top];
            top--;
        } else if (token[0] == '*') {
            stack[top-1] = stack[top-1] * stack[top];
            top--;
        } else {
            stack[++top] = atof(token);
        }
        token = strtok(NULL, " ");
    }
    double result = stack[top];
    // BUG 2: Missing free call
    return result;
}
EOF

    cat << 'EOF' > /home/user/input.txt
3 4 + 2 *
5 2 * 3 +
10 5 * 20 + 2 *
EOF

    chmod -R 777 /home/user
