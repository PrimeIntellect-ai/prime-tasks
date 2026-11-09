#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libseccomp-dev libssl-dev binutils
    pip3 install pytest

    # Create required directories
    mkdir -p /app/bin /app/data/in /app/data/out /tmp/malicious

    # Create dummy stripped binary for data_parser
    cat << 'EOF' > /tmp/parser.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    // Dummy implementation
    return 0;
}
EOF

    gcc -O2 -o /app/bin/data_parser /tmp/parser.c
    strip /app/bin/data_parser
    chmod 755 /app/bin/data_parser
    rm /tmp/parser.c

    # Create the user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
