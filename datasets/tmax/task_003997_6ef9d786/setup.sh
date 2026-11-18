#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc expect logrotate
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src /home/user/bin /home/user/daemon_logs

    cat << 'EOF' > /home/user/src/interactive_daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main() {
    // Disable buffering for stdout
    setbuf(stdout, NULL);

    char *env = getenv("DAEMON_ENV");
    if (env == NULL || strcmp(env, "hardened") != 0) {
        fprintf(stderr, "FATAL: DAEMON_ENV is not set to 'hardened'. Aborting.\n");
        return 1;
    }

    char pin[64];
    printf("Enter Hardening PIN: ");
    if (fgets(pin, sizeof(pin), stdin) != NULL) {
        pin[strcspn(pin, "\r\n")] = 0;
        if (strcmp(pin, "7924") == 0) {
            printf("PIN accepted. Daemon initialized.\n");
            while(1) {
                printf("STATUS: Daemon running securely...\n");
                sleep(1);
            }
        } else {
            fprintf(stderr, "FATAL: Invalid PIN.\n");
            return 1;
        }
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
