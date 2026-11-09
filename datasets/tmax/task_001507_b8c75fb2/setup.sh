#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/router.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <session_file>\n", argv[0]);
        return 1;
    }

    FILE *file = fopen(argv[1], "r");
    if (!file) {
        perror("Error opening file");
        return 1;
    }

    char session_data[256];
    if (fgets(session_data, sizeof(session_data), file) == NULL) {
        fclose(file);
        return 1;
    }
    fclose(file);

    session_data[strcspn(session_data, "\n")] = 0;

    // Token format validation
    if (strncmp(session_data, "TOKEN:", 6) != 0) {
        printf("Invalid session token.\n");
        return 1;
    }

    char *redirect = strstr(session_data, "next=");
    if (redirect) {
        redirect += 5;
        // Security check: ensure redirect is to a safe directory
        if (strncmp(redirect, "/opt/safe/", 10) == 0) {
            char command[512];
            // VULNERABILITY: No sanitization of the redirect path
            snprintf(command, sizeof(command), "/bin/bash %s", redirect);
            system(command);
        } else {
            printf("Security Error: Invalid redirect path.\n");
        }
    }

    return 0;
}
EOF

    mkdir -p /opt/safe
    chmod 755 /opt/safe

    chmod -R 777 /home/user
