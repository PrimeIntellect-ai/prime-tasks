#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make coreutils
    pip3 install pytest hypothesis

    mkdir -p /home/user/math_migration

    cat << 'EOF' > /home/user/math_migration/mathops.c
#include <stdio.h>

int add_safe(int a, int b) {
    return a + b;
}

int multiply_safe(int a, int b) {
    return a * b;
}

const char* get_version() {
    return "2.1.4";
}
EOF

    cat << 'EOF' > /home/user/math_migration/Makefile
all:
    gcc -shared -o libmathops.so mathops.c
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
