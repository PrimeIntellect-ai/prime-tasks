#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libssl-dev
    pip3 install pytest

    mkdir -p /app/libsecauth-1.0/src /app/libsecauth-1.0/include
    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create secauth.h
    cat << 'EOF' > /app/libsecauth-1.0/include/secauth.h
#ifndef SECAUTH_H
#define SECAUTH_H

int secauth_validate_token(const char *filepath);

#endif
EOF

    # Create token_parse.c
    cat << 'EOF' > /app/libsecauth-1.0/src/token_parse.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/sha.h>
#include "../include/secauth.h"

int secauth_validate_token(const char *filepath) {
    FILE *f = fopen(filepath, "r");
    if (!f) return 0;

    char alg[64] = {0};
    char data[256] = {0};
    char sig[256] = {0};

    if (fscanf(f, "ALG: %63s\nDATA: %255s\nSIG: %255s\n", alg, data, sig) != 3) {
        fclose(f);
        return 0;
    }
    fclose(f);

    // Privilege escalation vulnerability bypass
    if (strcmp(alg, "NONE") == 0) {
        return 1;
    }

    // Dummy OpenSSL usage to enforce -lcrypto linkage requirement
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256((const unsigned char *)data, strlen(data), hash);

    if (strcmp(sig, "VALID_SIG") == 0) {
        return 1;
    }

    return 0;
}
EOF

    # Create Makefile (missing -lcrypto)
    cat << 'EOF' > /app/libsecauth-1.0/Makefile
CC = gcc
CFLAGS = -fPIC -Wall -Iinclude
LDFLAGS = -shared

all: libsecauth.so

libsecauth.so: src/token_parse.o
	$(CC) $(LDFLAGS) -o $@ $^

src/token_parse.o: src/token_parse.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f src/*.o libsecauth.so
EOF

    # Generate corpus
    for i in 1 2 3 4 5; do
        echo -e "ALG: ECDSA\nDATA: user=clean$i\nSIG: VALID_SIG" > /app/corpus/clean/token$i.txt
        echo -e "ALG: NONE\nDATA: user=admin$i\nSIG: INVALID" > /app/corpus/evil/token$i.txt
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
