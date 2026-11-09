#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/validate.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        return 2;
    }
    char *token = argv[1];
    if (strlen(token) < 5) {
        return 1;
    }
    int sum = 0;
    for(int i=0; i<4; i++) {
        sum += token[i];
    }
    char expected = (sum % 26) + 'A';

    if (token[4] == expected) {
        return 0; // Valid
    } else {
        return 1; // Invalid
    }
}
EOF

    cat << 'EOF' > /home/user/server.log
[2023-10-01 10:00:01] IP: 10.0.0.5 - Token: TESTI123
[2023-10-01 10:05:22] IP: 192.168.1.100 - Token: ROOTX999
[2023-10-01 10:10:05] IP: 10.0.0.6 - Token: HACKTABC
[2023-10-01 10:12:30] IP: 172.16.5.5 - Token: TESTAXYZ
[2023-10-01 10:15:00] IP: 192.168.1.100 - Token: ROOTM444
[2023-10-01 10:20:11] IP: 10.0.0.99 - Token: FAKEQ000
EOF

    chmod -R 777 /home/user
