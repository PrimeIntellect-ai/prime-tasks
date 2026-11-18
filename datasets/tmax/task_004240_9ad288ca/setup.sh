#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy_router.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 5) {
        return 1;
    }

    char buffer[1024];
    snprintf(buffer, sizeof(buffer), "%s|%s|%s|%s", argv[1], argv[2], argv[3], argv[4]);

    int len = strlen(buffer);
    for (int i = len - 1; i >= 0; i--) {
        printf("%02x", (unsigned char)buffer[i]);
    }
    printf("\n");
    return 0;
}
EOF

    gcc /tmp/legacy_router.c -o /app/legacy_router_configurator
    strip /app/legacy_router_configurator
    chmod +x /app/legacy_router_configurator
    rm /tmp/legacy_router.c

    echo "Etc/UTC" > /etc/timezone
    mkdir -p /etc/default
    echo "LANG=en_US.UTF-8" > /etc/default/locale

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
