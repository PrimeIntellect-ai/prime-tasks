#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/project/src

    cat << 'EOF' > /home/user/project/src/eval.c
#include <string.h>

int evaluate(const char* op, int a, int b) {
    if (strcmp(op, "ADD") == 0) return a + b;
    if (strcmp(op, "SUB") == 0) return a - b;
    if (strcmp(op, "MUL") == 0) return a * b;
    if (strcmp(op, "DIV") == 0) return b != 0 ? a / b : 0;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/Makefile
all: libeval.so

libeval.so: src/eval.c
	gcc src/eval.c -o libeval.so
EOF
    # Ensure Makefile uses a real tab
    sed -i 's/^    /\t/' /home/user/project/Makefile

    cat << 'EOF' > /home/user/project/data.txt
ADD 15 25
MUL 4 7
SUB 100 42
DIV 50 2
ADD -5 15
MUL 0 99
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
