#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        libssl-dev \
        gawk \
        coreutils

    pip3 install pytest requests flask fastapi uvicorn

    useradd -m -s /bin/bash user || true

    # Create the legacy binary
    mkdir -p /app
    cat << 'EOF' > /app/acl_checker.c
#include <stdio.h>
#include <string.h>
#include <openssl/sha.h>

int main(int argc, char **argv) {
    if (argc < 3) return 1;
    char buf[4096];
    snprintf(buf, sizeof(buf), "%s%s", argv[1], argv[2]);
    unsigned char hash[SHA_DIGEST_LENGTH];
    SHA1((unsigned char*)buf, strlen(buf), hash);
    if (hash[0] == 0) return 0;
    return 1;
}
EOF
    gcc -O2 /app/acl_checker.c -o /app/acl_checker -lcrypto
    strip /app/acl_checker
    rm /app/acl_checker.c

    # Create files for integrity checks
    echo "This is a valid file." > /home/user/valid.txt
    echo "This is the original content." > /home/user/modified.txt

    VALID_HASH=$(sha256sum /home/user/valid.txt | awk '{print $1}')
    MODIFIED_HASH=$(sha256sum /home/user/modified.txt | awk '{print $1}')

    echo "$VALID_HASH  /home/user/valid.txt" > /home/user/secure_ledger.txt
    echo "$MODIFIED_HASH  /home/user/modified.txt" >> /home/user/secure_ledger.txt

    # Modify the file so the hash no longer matches
    echo "This content has been maliciously modified." > /home/user/modified.txt

    chmod -R 777 /home/user
