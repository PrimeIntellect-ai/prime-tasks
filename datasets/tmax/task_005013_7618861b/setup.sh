#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev
    pip3 install pytest flask fastapi uvicorn pandas requests

    mkdir -p /app
    cat << 'EOF' > /tmp/hasher.c
#include <stdio.h>
#include <string.h>
#include <openssl/evp.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char buffer[1024];
    snprintf(buffer, sizeof(buffer), "%s_config_salt_99", argv[1]);

    EVP_MD_CTX *mdctx = EVP_MD_CTX_new();
    const EVP_MD *md = EVP_md5();
    unsigned char md_value[EVP_MAX_MD_SIZE];
    unsigned int md_len;

    EVP_DigestInit_ex(mdctx, md, NULL);
    EVP_DigestUpdate(mdctx, buffer, strlen(buffer));
    EVP_DigestFinal_ex(mdctx, md_value, &md_len);
    EVP_MD_CTX_free(mdctx);

    for(unsigned int i = 0; i < md_len; i++)
        printf("%02x", md_value[i]);
    printf("\n");
    return 0;
}
EOF
    gcc -o /app/config_hasher /tmp/hasher.c -lcrypto
    strip /app/config_hasher
    chmod +x /app/config_hasher
    rm /tmp/hasher.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
