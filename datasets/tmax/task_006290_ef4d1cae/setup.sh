#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ jq coreutils
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > libexpr.c
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

int evaluate_postfix(const char* expr) {
    int stack[100];
    int top = -1;
    for(int i=0; expr[i]; i++) {
        if(isdigit(expr[i])) {
            stack[++top] = expr[i] - '0';
        } else if(expr[i] == '+') {
            int b = stack[top--];
            int a = stack[top--];
            stack[++top] = a + b;
        } else if(expr[i] == '-') {
            int b = stack[top--];
            int a = stack[top--];
            stack[++top] = a - b;
        } else if(expr[i] == '*') {
            int b = stack[top--];
            int a = stack[top--];
            stack[++top] = a * b;
        }
    }
    return stack[top];
}
EOF

    gcc -shared -fPIC -o libexpr.so libexpr.c

    cat << 'EOF' > expr.h
#ifndef EXPR_H
#define EXPR_H

int evaluate_postfix(const char* expr);

#endif
EOF

    cat << 'EOF' > evaluator.cpp
#include <iostream>
#include <string>
#include "expr.h"

int main(int argc, char** argv) {
    if(argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <expression>\n";
        return 1;
    }
    std::cout << evaluate_postfix(argv[1]) << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > v1_schema.txt
OCAyICs=
NyAzICogMiAr
OSA0IC0gNSAq
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
