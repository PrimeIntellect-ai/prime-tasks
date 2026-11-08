#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils jq coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/worker.c
#include <stdio.h>

__attribute__((section(".malconf"))) 
const char payload[] = "MjAzLjAuMTEzLjQyLDE5OC41MS4xMDAuMTcsMTkyLjAuMi4yMTU=";

int main() {
    printf("Starting web worker...\n");
    return 0;
}
EOF

    gcc -o /home/user/suspicious_web_worker.elf /tmp/worker.c
    rm /tmp/worker.c

    chmod -R 777 /home/user
