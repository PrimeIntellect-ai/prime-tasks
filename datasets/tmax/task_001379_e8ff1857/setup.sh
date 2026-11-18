#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libssl-dev
    pip3 install pytest

    # Create vendored package directory
    mkdir -p /app/vendored-sso-auth-1.2.0

    # Create C source for sso-decrypt
    cat << 'EOF' > /app/vendored-sso-auth-1.2.0/sso-decrypt.c
#include <stdio.h>
#include <stdlib.h>
#include <openssl/md5.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <file>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("fopen");
        return 1;
    }
    char buffer[1024];
    if (fgets(buffer, sizeof(buffer), f)) {
        // Print the content (simulating decryption)
        printf("%s", buffer);
    }
    fclose(f);

    // Dummy openssl call to require linking
    MD5_CTX c;
    MD5_Init(&c);

    return 0;
}
EOF

    # Create Makefile with the perturbation
    cat << 'EOF' > /app/vendored-sso-auth-1.2.0/Makefile
LD_FLAGS=-L/opt/old_crypto/lib
CFLAGS=-O2

all: sso-decrypt

sso-decrypt: sso-decrypt.c
	gcc $(CFLAGS) -o sso-decrypt sso-decrypt.c $(LD_FLAGS) -lssl -lcrypto
EOF

    # Create corpus directories
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Create evil corpus files
    echo -n "https://malicious.com/login" > /app/corpus/evil/token_evil_1.txt
    echo -n "//phishing.net" > /app/corpus/evil/token_evil_2.txt
    echo -n "javascript:alert(1)" > /app/corpus/evil/token_evil_3.txt
    echo -n "http://evil.com/redirect" > /app/corpus/evil/token_evil_4.txt

    # Create clean corpus files
    echo -n "/home" > /app/corpus/clean/token_clean_1.txt
    echo -n "/profile?user=123" > /app/corpus/clean/token_clean_2.txt
    echo -n "/settings" > /app/corpus/clean/token_clean_3.txt
    echo -n "/dashboard/reports" > /app/corpus/clean/token_clean_4.txt

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /app
    chmod -R 777 /home/user
