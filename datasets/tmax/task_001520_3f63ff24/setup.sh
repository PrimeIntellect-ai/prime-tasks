#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git imagemagick gcc
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/repo
    cd /home/user/repo

    git config --global init.defaultBranch main
    git config --global user.email "dev@example.com"
    git config --global user.name "Developer"

    git init
    cat << 'EOF' > transform.py
import sys
for line in sys.stdin:
    print(line.strip()[::-1])
EOF
    git add transform.py
    git commit -m "Initial working version of string reverser"

    rm transform.py
    echo "binary data placeholder" > oracle.bin
    git add -A
    git commit -m "Migrate to compiled binary and remove source"

    # Create the Image Fixture
    convert -size 500x150 xc:white -fill black -pointsize 24 -draw "text 20,70 'Please use prefix: XYLON-774:'" /app/ticket_screenshot.png

    # Create the Oracle Binary
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <string.h>

int main() {
    char buffer[256];
    while (fgets(buffer, sizeof(buffer), stdin)) {
        buffer[strcspn(buffer, "\n")] = 0; // Strip newline
        printf("XYLON-774:");
        for (int i = strlen(buffer) - 1; i >= 0; i--) {
            putchar(buffer[i]);
        }
        putchar('\n');
    }
    return 0;
}
EOF
    gcc /tmp/oracle.c -o /app/oracle_bin
    rm /tmp/oracle.c
    chmod 755 /app/oracle_bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
