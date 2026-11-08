#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        git \
        expect \
        cargo

    pip3 install pytest

    # Create the proprietary administration tool
    mkdir -p /app
    cat << 'EOF' > /app/lb_admin.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main() {
    char buf[256];
    printf("Username: ");
    fflush(stdout);
    if (!fgets(buf, sizeof(buf), stdin)) return 1;
    if (strcmp(buf, "admin\n") != 0) return 1;

    printf("Password: ");
    fflush(stdout);
    if (!fgets(buf, sizeof(buf), stdin)) return 1;
    if (strcmp(buf, "secret123\n") != 0) return 1;

    while (1) {
        printf("lb-cli> ");
        fflush(stdout);
        if (!fgets(buf, sizeof(buf), stdin)) break;
        if (strcmp(buf, "reload config\n") == 0) {
            system("mkdir -p /home/user/lb_config && touch /home/user/lb_config/reload_flag");
            printf("Configuration reloaded successfully.\n");
        } else if (strcmp(buf, "quit\n") == 0) {
            break;
        } else {
            printf("Unknown command.\n");
        }
    }
    return 0;
}
EOF
    gcc -O2 /app/lb_admin.c -o /app/lb_admin
    strip /app/lb_admin
    rm /app/lb_admin.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
