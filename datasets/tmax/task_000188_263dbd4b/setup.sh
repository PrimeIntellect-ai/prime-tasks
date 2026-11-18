#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc expect
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_daemon.c
#include <stdio.h>
#include <string.h>

int main() {
    char input[256];

    printf("Welcome to the Legacy Migration Daemon\n");
    printf("Enter Auth Key: ");
    fflush(stdout);
    if (fgets(input, sizeof(input), stdin) == NULL) return 1;
    input[strcspn(input, "\n")] = 0;

    if (strcmp(input, "cloud_admin_99") != 0) {
        printf("Auth failed.\n");
        return 1;
    }

    printf("Command: ");
    fflush(stdout);
    if (fgets(input, sizeof(input), stdin) == NULL) return 1;

    printf("Target IP: ");
    fflush(stdout);
    if (fgets(input, sizeof(input), stdin) == NULL) return 1;
    input[strcspn(input, "\n")] = 0;

    printf("\nSUCCESS: Migration started to %s\n", input);
    return 0;
}
EOF

    chmod -R 777 /home/user
