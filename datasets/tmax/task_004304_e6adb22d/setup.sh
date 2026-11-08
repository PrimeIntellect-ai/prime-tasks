#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make openssl libssl-dev
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/inspector.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <regex.h>

int main() {
    char buffer[4096];
    size_t bytes_read = fread(buffer, 1, sizeof(buffer) - 1, stdin);
    buffer[bytes_read] = '\0';

    regex_t regex;
    int reti;

    reti = regcomp(&regex, "Referer: .*//[^/]+/%2e%2e", REG_EXTENDED);
    if (reti) {
        fprintf(stderr, "Could not compile regex\n");
        exit(1);
    }

    reti = regexec(&regex, buffer, 0, NULL, 0);
    if (!reti) {
        // Match found, simulate crash
        char *crash = NULL;
        *crash = 1;
    } else if (reti == REG_NOMATCH) {
        printf("CLEAN\n");
    }

    regfree(&regex);
    return 0;
}
EOF

    gcc -s /tmp/inspector.c -o /app/traffic_inspector
    rm /tmp/inspector.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
