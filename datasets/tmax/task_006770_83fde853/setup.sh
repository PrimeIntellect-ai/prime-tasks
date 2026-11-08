#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/rules.txt
FORWARD 8080 80
FORWARD 9000 9000
INVALID_LINE missing ports
DROP 22 -1
FORWARD abc def
FORWARD 443 8443
DROP 23
EOF

    cat << 'EOF' > /home/user/net_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char action[50];
    int p1, p2;
    // BUG: fscanf doesn't clear the buffer properly on failure, and doesn't check return value
    while (!feof(f)) {
        fscanf(f, "%s %d %d", action, &p1, &p2);
        printf("[VALID] %s %d %d\n", action, p1, p2);
    }
    fclose(f);
    return 0;
}
EOF

    chmod -R 777 /home/user
