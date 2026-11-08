#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk coreutils binutils
    pip3 install pytest

    # Create the legacy_hasher binary
    mkdir -p /app
    cat << 'EOF' > /app/legacy_hasher.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "echo -n '%s' | md5sum | awk '{print $1}' | rev", argv[1]);
    int ret = system(cmd);
    return ret;
}
EOF

    gcc -O2 /app/legacy_hasher.c -o /app/legacy_hasher
    strip /app/legacy_hasher
    rm /app/legacy_hasher.c
    chmod +x /app/legacy_hasher

    # Create user and home directory
    useradd -m -s /bin/bash user || true

    # Touch the log file
    touch /home/user/etl_metrics.log

    chmod -R 777 /home/user
