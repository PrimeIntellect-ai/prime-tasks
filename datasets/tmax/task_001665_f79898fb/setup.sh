#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/upload_handler.c
#include <stdio.h>
#include <string.h>

void sanitize(char *str) {
    char buffer[4096] = {0};
    char *src = str;
    char *match;
    while ((match = strstr(src, "../")) != NULL) {
        strncat(buffer, src, match - src);
        src = match + 3;
    }
    strcat(buffer, src);
    strcpy(str, buffer);
}

int main(int argc, char **argv) {
    if (argc > 1) {
        char input[4096];
        strncpy(input, argv[1], 4095);
        input[4095] = '\0';
        sanitize(input);
        printf("%s\n", input);
    }
    return 0;
}
EOF

    gcc -O2 -s -o /app/upload_handler /tmp/upload_handler.c
    rm /tmp/upload_handler.c
    chmod +x /app/upload_handler

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
