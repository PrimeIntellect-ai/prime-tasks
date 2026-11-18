#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the vulnerable C code
    cat << 'EOF' > /home/user/service.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void parse_telemetry(const char *msg) {
    if (msg == NULL || strlen(msg) == 0) return;

    char *buffer = malloc(512);
    if (!buffer) return;
    strncpy(buffer, msg, 511);
    buffer[511] = '\0';

    // If message starts with 'Z', it indicates a nested telemetry layer.
    // BUG: Infinite recursion here because we pass 'msg' instead of 'msg + 1',
    // allocating 512 bytes on every stack frame until OOM.
    if (buffer[0] == 'Z') {
        parse_telemetry(msg); 
    } else {
        printf("Processed: %s\n", buffer);
    }

    free(buffer);
}

int main() {
    char input[256];
    if (fgets(input, sizeof(input), stdin)) {
        // Remove newline
        input[strcspn(input, "\n")] = 0;
        parse_telemetry(input);
    }
    return 0;
}
EOF

    # Create the memory dump with random binary garbage and the hidden string
    head -c 1M /dev/urandom > /home/user/memory.dump
    echo -n "CRASH_PAYLOAD:ZZZZ_MALFORMED_DATA_99182" >> /home/user/memory.dump
    head -c 1M /dev/urandom >> /home/user/memory.dump

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
