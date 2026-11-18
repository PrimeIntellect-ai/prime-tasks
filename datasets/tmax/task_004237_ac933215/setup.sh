#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install --default-timeout=100 pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/meta_bridge.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    unsigned long hash = 5381;
    int c;
    char *str = argv[1];
    while ((c = *str++))
        hash = ((hash << 5) + hash) + c;
    printf("GRAPH_NODE_%lx\n", hash);
    return 0;
}
EOF
    gcc -O2 /tmp/meta_bridge.c -o /app/meta_bridge
    strip /app/meta_bridge
    rm /tmp/meta_bridge.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
