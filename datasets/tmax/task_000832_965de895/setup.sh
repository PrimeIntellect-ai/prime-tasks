#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev binutils xxd
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/token_gen.c
#include <stdio.h>
#include <string.h>
#include <openssl/md5.h>

int main(int argc, char *argv[]) {
    if(argc != 3) return 1;
    char buffer[256];
    snprintf(buffer, sizeof(buffer), "%s:%s", argv[1], argv[2]);
    unsigned char digest[MD5_DIGEST_LENGTH];
    MD5((unsigned char*)buffer, strlen(buffer), digest);
    for(int i = 0; i < MD5_DIGEST_LENGTH; i++)
        printf("%02x", digest[i]);
    printf("\n");
    return 0;
}
EOF
    gcc -O2 -s /tmp/token_gen.c -o /app/token_gen -lcrypto
    rm /tmp/token_gen.c

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_logs.py
import random
import hashlib

def generate():
    with open("/home/user/redirect_logs.txt", "w") as f:
        for _ in range(500):
            thumbprint = "".join(random.choices("0123456789abcdef", k=10))
            pin = f"{random.randint(0, 9999):04d}"
            test_str = f"{thumbprint}:{pin}".encode('utf-8')
            token = hashlib.md5(test_str).hexdigest()
            f.write(f"{thumbprint},{token}\n")

if __name__ == "__main__":
    generate()
EOF
    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    chmod -R 777 /home/user
