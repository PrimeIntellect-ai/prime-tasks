#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make nginx curl
    pip3 install pytest websockets packaging

    mkdir -p /home/user/workspace/c_src /home/user/workspace/backend /home/user/workspace/lib /home/user/workspace/nginx

    cat << 'EOF' > /home/user/workspace/c_src/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char* parse_message(const char* input) {
    char buffer[128]; // Vulnerable buffer
    sprintf(buffer, "{PROCESSED: %s}", input); // Buffer overflow if input is large
    return strdup(buffer);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
