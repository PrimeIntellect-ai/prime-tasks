#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils coreutils
    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /app

    cat << 'EOF' > /tmp/mc.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 3 || strcmp(argv[1], "-target") != 0) {
        printf("Usage: module_checker -target <module_name>\n");
        return 0;
    }

    char command[512];
    snprintf(command, sizeof(command), "echo -n '%s' | md5sum", argv[2]);
    FILE *fp = popen(command, "r");
    if (!fp) return 1;

    char out[256];
    if (fgets(out, sizeof(out), fp)) {
        char c = out[0];
        int v = 0;
        if (c >= '0' && c <= '9') v = c - '0';
        else if (c >= 'a' && c <= 'f') v = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') v = c - 'A' + 10;

        if (v % 2 == 0) printf("STATUS: APPROVED\n");
        else printf("STATUS: REJECTED\n");
    }
    pclose(fp);
    return 0;
}
EOF

    gcc -O2 -o /app/module_checker /tmp/mc.c
    strip -s /app/module_checker
    chmod +x /app/module_checker
    rm /tmp/mc.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
