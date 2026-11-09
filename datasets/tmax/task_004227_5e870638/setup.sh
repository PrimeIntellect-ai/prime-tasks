#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev openssl coreutils

    # Increase timeout to prevent ReadTimeoutError
    pip3 install --default-timeout=100 pytest

    mkdir -p /app

    # Create the legacy C source code
    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/sha.h>
#include <openssl/evp.h>
#include <openssl/bio.h>
#include <openssl/buffer.h>

size_t calcDecodeLength(const char* b64input) {
    size_t len = strlen(b64input), padding = 0;
    if (len > 0 && b64input[len-1] == '=' && b64input[len-2] == '=') padding = 2;
    else if (len > 0 && b64input[len-1] == '=') padding = 1;
    return (len*3)/4 - padding;
}

int Base64Decode(const char* b64message, unsigned char** buffer, size_t* length) {
    BIO *bio, *b64;
    int decodeLen = calcDecodeLength(b64message);
    *buffer = (unsigned char*)malloc(decodeLen + 1);
    if (*buffer == NULL) return 1;
    (*buffer)[decodeLen] = '\0';

    bio = BIO_new_mem_buf(b64message, -1);
    b64 = BIO_new(BIO_f_base64());
    bio = BIO_push(b64, bio);
    BIO_set_flags(bio, BIO_FLAGS_BASE64_NO_NL);
    *length = BIO_read(bio, *buffer, strlen(b64message));
    BIO_free_all(bio);
    return 0;
}

int main() {
    char input[1024];
    if (!fgets(input, sizeof(input), stdin)) return 1;
    input[strcspn(input, "\r\n")] = 0;

    unsigned char* decoded = NULL;
    size_t dec_len = 0;
    if (Base64Decode(input, &decoded, &dec_len) != 0) return 1;

    const char* salt = "!SecR0t@t1on#";
    size_t salt_len = strlen(salt);

    unsigned char* combined = malloc(dec_len + salt_len);
    if (combined == NULL) return 1;
    memcpy(combined, decoded, dec_len);
    memcpy(combined + dec_len, salt, salt_len);

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(combined, dec_len + salt_len, hash);

    for(int i = 0; i < SHA256_DIGEST_LENGTH; i++) {
        printf("%02x", hash[i]);
    }
    printf("\n");

    free(decoded);
    free(combined);
    return 0;
}
EOF

    # Compile and strip the legacy binary
    gcc -O3 -o /app/credgen_legacy /tmp/legacy.c -lcrypto
    strip /app/credgen_legacy
    rm /tmp/legacy.c

    # Generate 100,000 base64 seeds
    python3 -c '
import base64, os
with open("/app/seeds.txt", "w") as f:
    for _ in range(100000):
        f.write(base64.b64encode(os.urandom(16)).decode("utf-8") + "\n")
'

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
