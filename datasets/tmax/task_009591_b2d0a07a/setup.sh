#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/src/math_check.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <number>\n", argv[0]);
        return 1;
    }

    int n = atoi(argv[1]);

    // Deliberately use pow to require -lm
    int val = (int)pow((double)n, 2.0) + 15;

    char cmd[256];
    // Output base64 encoded value without trailing newline from echo
    snprintf(cmd, sizeof(cmd), "echo -n '%d' | base64", val);
    int ret = system(cmd);

    return ret == 0 ? 0 : 1;
}
EOF

    chmod -R 777 /home/user
