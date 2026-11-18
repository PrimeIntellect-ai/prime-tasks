#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb binutils build-essential
    pip3 install pytest

    # Create directory for the oracle
    mkdir -p /app

    # Create the oracle source code
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("0\n");
        return 0;
    }
    char *str = argv[1];
    int score = 0;
    int len = strlen(str);
    for (int i = 0; i < len; i++) {
        char c = str[i];
        if (c >= 'A' && c <= 'Z') {
            score += (c - 'A' + 1);
        } else if (c >= '0' && c <= '9') {
            score -= (c - '0');
        } else if (c == ' ') {
            score += 5;
        }
    }
    if (len > 10) {
        score -= 10;
    }
    printf("%d\n", score);
    return 0;
}
EOF

    # Compile the oracle binary
    gcc -O2 /tmp/oracle.c -o /app/firewall_validator_oracle
    rm /tmp/oracle.c
    chmod +x /app/firewall_validator_oracle

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
