#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/auth_module.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void log_access(const char* user) {
    char buffer[50];
    // Vulnerable string copy
    strcpy(buffer, user);
    printf("Access logged: %s\n", buffer);
}

void format_output(char* out, int val) {
    sprintf(out, "Value is %d", val);
}

int main() {
    char input[100];
    printf("Enter username: ");
    gets(input);

    log_access(input);

    char out[50];
    format_output(out, 42);

    return 0;
}
EOF

    python3 -c '
plaintext = b"SECURE_LOG_V1\nUSER: admin_service\nACTION: DEPLOY\nSECRET: TOKEN-X9Y8Z7A6B5C4D3E2\nSTATUS: SUCCESS\n"
key = b"csec"
encrypted = bytearray()
for i in range(len(plaintext)):
    encrypted.append(plaintext[i] ^ key[i % len(key)])

with open("/home/user/project/audit_log.enc", "wb") as f:
    f.write(encrypted)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
