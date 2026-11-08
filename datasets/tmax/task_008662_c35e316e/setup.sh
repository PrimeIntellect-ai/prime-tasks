#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/polybuild

    cat << 'EOF' > /home/user/polybuild/math_ops.c
#include <stdint.h>

int32_t op_add(int32_t a, int32_t b) {
    return a + b;
}

int32_t op_sub(int32_t a, int32_t b) {
    return a - b;
}

int32_t op_mul(int32_t a, int32_t b) {
    return a * b;
}

int32_t op_div(int32_t a, int32_t b) {
    if (b == 0) return 0;
    return a / b;
}
EOF

    cat << 'EOF' > /home/user/polybuild/poly.dsl
BUILD shared op_lib math_ops.c
EVAL op_lib (op_add (op_mul 12 13) (op_sub 50 (op_div 120 4)))
EOF

    chmod -R 777 /home/user
