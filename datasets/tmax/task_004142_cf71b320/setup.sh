#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils socat netcat-openbsd bc jq gawk coreutils
    pip3 install pytest

    # Create dataset
    mkdir -p /home/user/dataset
    cat << 'EOF' > /home/user/dataset/logs.txt
login failed admin
session opened root
invalid user test
sql syntax error
connection timed out
failed password root
successful login user
EOF
    chmod 644 /home/user/dataset/logs.txt

    # Create oracle binary
    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("ERROR\n");
        return 1;
    }
    if (strstr(argv[1], "failed") || strstr(argv[1], "invalid") || strstr(argv[1], "error")) {
        printf("MALICIOUS\n");
    } else {
        printf("BENIGN\n");
    }
    return 0;
}
EOF
    gcc -static -O2 /app/oracle.c -o /app/log_oracle
    strip /app/log_oracle
    rm /app/oracle.c
    chmod 755 /app/log_oracle

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
