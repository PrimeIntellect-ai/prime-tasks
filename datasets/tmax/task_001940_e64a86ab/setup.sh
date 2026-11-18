#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /home/user/configs /home/user/configs_high /home/user/configs_low
    mkdir -p /app

    cat << 'EOF' > /tmp/eval.c
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Extremely basic mock for the verifier environment
// In reality this would be a full parser.
double evaluate_expr_v2(const char* expr) {
    // Mock logic: if it contains "100 * 50 + 20", return 5020.0
    // If it's a number, return the number.
    if (strstr(expr, "100 * 50 + 20")) return 5020.0;
    if (strstr(expr, "10+20*3")) return 70.0;
    return atof(expr);
}
EOF
    gcc -shared -fPIC -O2 /tmp/eval.c -o /app/libevaluator.so
    strip /app/libevaluator.so

    echo "50 * 3" > /home/user/configs/file1.txt
    echo "10 + 20" > /home/user/configs/file2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
