#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev binutils curl
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/manifest_compiler.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[256];
    char name[256] = {0};
    int replicas = -1;
    while (fgets(line, sizeof(line), f)) {
        char *p;
        if ((p = strstr(line, "name: "))) {
            sscanf(p, "name: %s", name);
        }
        if ((p = strstr(line, "replicas: "))) {
            sscanf(p, "replicas: %d", &replicas);
        }
    }
    fclose(f);
    if (strlen(name) > 0 && replicas >= 0) {
        printf("COMPILED:%s:%d\n", name, replicas * 2);
        return 0;
    }
    return 1;
}
EOF
    gcc -O3 -s /app/manifest_compiler.c -o /app/manifest_compiler
    rm /app/manifest_compiler.c

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/manifests /home/user/backups
    chmod -R 777 /home/user
    chmod -R 777 /app
