#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc strace
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > vulnerable_backend.c
#include <stdio.h>
#include <string.h>

void encrypt_data(const char* input, char* output) {
    char key = 0x5A; // The XOR key is 0x5A (90)
    int len = strlen(input);
    for(int i = 0; i < len; i++) {
        output[i] = input[i] ^ key;
    }
}

int main() {
    printf("Backend initialized. Key loaded.\n");
    return 0;
}
EOF

    gcc -o vulnerable_backend vulnerable_backend.c
    rm vulnerable_backend.c

    python3 -c '
key = 0x5A
plaintext = "Patient records show John Doe has SSN 123-45-6789 and Jane Doe has SSN 987-65-4321. Do not share."
encrypted = bytes([ord(c) ^ key for c in plaintext])
with open("/home/user/encrypted.dat", "wb") as f:
    f.write(encrypted)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
