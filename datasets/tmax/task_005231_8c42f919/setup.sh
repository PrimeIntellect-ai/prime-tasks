#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc socat netcat-openbsd nginx patch
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/math_pipeline

    cat << 'EOF' > /home/user/math_pipeline/factorial.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    int n;
    if (scanf("%d", &n) != 1) return 1;

    int result = 1;
    for (int i = 1; i <= n; i++) {
        result *= i;
    }

    printf("%d\n", result);
    return 0;
}
EOF

    chmod -R 777 /home/user
