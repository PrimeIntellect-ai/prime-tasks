#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc socat netcat-openbsd
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/log_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[1024];
    int count = 0;
    while (fgets(line, sizeof(line), stdin)) {
        if (strstr(line, "CORRUPT")) {
            while(1) {} // hang
        }
        printf("PROCESSED: %s", line);
        fflush(stdout);
        count++;
        if (count > 20) {
            abort(); // simulate crash
        }
    }
    return 0;
}
EOF
    gcc -O2 /app/log_parser.c -o /app/log_parser
    strip /app/log_parser
    rm /app/log_parser.c
    chmod +x /app/log_parser

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
