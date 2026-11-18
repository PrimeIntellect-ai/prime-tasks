#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_auth_app

    cat << 'EOF' > /home/user/legacy_auth_app/creds.conf
DB_PASS=OldPass123
EOF

    cat << 'EOF' > /home/user/legacy_auth_app/app.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char *query = getenv("QUERY_STRING");
    char username[256] = {0};

    printf("Content-Type: text/html\n\n");

    if (query != NULL && strncmp(query, "username=", 9) == 0) {
        strncpy(username, query + 9, 255);
    } else {
        printf("<html><body>Missing username</body></html>\n");
        return 1;
    }

    // Vulnerability 1: Command Injection
    char cmd[512];
    sprintf(cmd, "echo 'Login attempt for %s' >> /tmp/auth.log", username);
    system(cmd);

    // Vulnerability 2: Reflected XSS
    printf("<html><body>Login failed for user: %s</body></html>\n", username);

    return 0;
}
EOF

    chmod -R 777 /home/user
    chmod 0666 /home/user/legacy_auth_app/creds.conf
