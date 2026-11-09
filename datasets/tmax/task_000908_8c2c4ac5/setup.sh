#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/emitter.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    FILE *f = fopen("health.log", "a");
    if (!f) return 1;
    fprintf(f, "status=OK\n");
    fclose(f);
    return 0;
}
EOF

    chmod -R 777 /home/user
