#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /app/traffic/clean /app/traffic/evil

# Create vulnerable C program
cat << 'EOF' > /app/auth_checker.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    char buffer[1024];
    FILE *f = stdin;
    if (argc > 1) {
        f = fopen(argv[1], "r");
        if (!f) return 1;
    }

    char *session = NULL;
    while (fgets(buffer, sizeof(buffer), f)) {
        if (strncmp(buffer, "X-Auth-Session: ", 16) == 0) {
            session = strdup(buffer + 16);
            break;
        }
    }
    if (f != stdin) fclose(f);

    if (!session) return 1;

    char *user = NULL;
    char *role = NULL;
    char *mac = NULL;

    char *token = strtok(session, ";\r\n");
    while (token) {
        if (strncmp(token, "user=", 5) == 0 && !user) user = token + 5;
        if (strncmp(token, "role=", 5) == 0) role = token + 5; // Vulnerability: overwrites previous
        if (strncmp(token, "mac=", 4) == 0 && !mac) mac = token + 4;
        token = strtok(NULL, ";\r\n");
    }

    if (!user || !role || !mac) return 1;

    if (strcmp(role, "admin") == 0) return 0;
    return 1;
}
EOF

gcc -O2 -o /app/auth_checker /app/auth_checker.c
strip --strip-all /app/auth_checker
rm /app/auth_checker.c

# Generate traffic
python3 -c '
import os
clean_dir = "/app/traffic/clean"
evil_dir = "/app/traffic/evil"

for i in range(50):
    with open(os.path.join(clean_dir, f"req_{i}.txt"), "w") as f:
        f.write(f"GET / HTTP/1.1\r\nHost: example.com\r\nX-Auth-Session: user=user{i};role=user;mac=abcdef\r\n\r\n")

for i in range(50):
    with open(os.path.join(evil_dir, f"req_{i}.txt"), "w") as f:
        f.write(f"GET /admin HTTP/1.1\r\nHost: example.com\r\nX-Auth-Session: user=user{i};role=user;mac=abcdef;role=admin\r\n\r\n")
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
