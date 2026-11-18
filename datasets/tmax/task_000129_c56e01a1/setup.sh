#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/backdoor.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void decrypt_evidence() {
    system("base64 -d /home/user/evidence.enc > /home/user/recovered.dat 2>/dev/null");
    printf("Evidence decrypted.\n");
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <password>\n", argv[0]);
        return 1;
    }

    char *pass = argv[1];
    if (strlen(pass) != 10) {
        printf("Invalid length.\n");
        return 1;
    }

    int sum = 0;
    for(int i=0; i<10; i++) {
        sum += pass[i];
    }

    if (sum == 900 && pass[0] == 'F' && pass[9] == 'X') {
        decrypt_evidence();
    } else {
        printf("Invalid password.\n");
    }

    return 0;
}
EOF

    echo "Q09ORklERU5USUFMX0ZPUkVOU0lDX0RBVEFfNzc4ODk5Cg==" > /home/user/evidence.enc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
