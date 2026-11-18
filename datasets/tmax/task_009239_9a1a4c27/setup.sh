#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gcc jq
    pip3 install pytest

    mkdir -p /home/user/configs
    echo "B.txt + C.txt" > /home/user/configs/A.txt
    echo "10 * 2" > /home/user/configs/B.txt
    echo "D.txt - 5" > /home/user/configs/C.txt
    echo "15" > /home/user/configs/D.txt
    echo "A.txt / 2" > /home/user/configs/E.txt
    echo "100" > /home/user/configs/F.txt

    cat << 'EOF' > /home/user/math_ops.h
#ifndef MATH_OPS_H
#define MATH_OPS_H
int evaluate_op(int a, int b, char op);
#endif
EOF

    cat << 'EOF' > /home/user/math_ops.c
#include "math_ops.h"
int evaluate_op(int a, int b, char op) {
    if (op == '+') return a + b;
    if (op == '-') return a - b;
    if (op == '*') return a * b;
    if (op == '/') return b != 0 ? a / b : 0;
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
