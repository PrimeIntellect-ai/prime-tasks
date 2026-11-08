#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev binutils strace ltrace xxd gawk sed coreutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/waf_evasion_encoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/md5.h>
#include <openssl/evp.h>

void reverse_string(char *str) {
    int n = strlen(str);
    for (int i = 0; i < n / 2; i++) {
        char temp = str[i];
        str[i] = str[n - i - 1];
        str[n - i - 1] = temp;
    }
}

int base64_encode(const unsigned char *buffer, size_t length, char **b64text) {
    EVP_ENCODE_CTX *ctx = EVP_ENCODE_CTX_new();
    int outlen = 4 * ((length + 2) / 3) + 1;
    *b64text = (char *)malloc(outlen);
    int outl, tmplen;

    EVP_EncodeInit(ctx);
    EVP_EncodeUpdate(ctx, (unsigned char *)*b64text, &outl, buffer, length);
    EVP_EncodeFinal(ctx, (unsigned char *)*b64text + outl, &tmplen);
    outlen = outl + tmplen;
    (*b64text)[outlen] = '\0';

    // Remove newlines added by EVP_EncodeUpdate
    int j = 0;
    for (int i = 0; i < outlen; i++) {
        if ((*b64text)[i] != '\n') {
            (*b64text)[j++] = (*b64text)[i];
        }
    }
    (*b64text)[j] = '\0';

    EVP_ENCODE_CTX_free(ctx);
    return j;
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        return 1;
    }

    char *input = strdup(argv[1]);
    reverse_string(input);

    char *b64_str;
    base64_encode((unsigned char*)input, strlen(input), &b64_str);

    char salt[] = "_WAF_BYPASS_S4LT_2024";
    char *to_hash = malloc(strlen(b64_str) + strlen(salt) + 1);
    strcpy(to_hash, b64_str);
    strcat(to_hash, salt);

    unsigned char digest[MD5_DIGEST_LENGTH];
    MD5((unsigned char*)to_hash, strlen(to_hash), digest);

    printf("[AUTH-TOKEN: ");
    for(int i = 0; i < MD5_DIGEST_LENGTH; i++) {
        printf("%02x", digest[i]);
    }
    printf("]|PAYLOAD:%s\n", b64_str);

    free(input);
    free(b64_str);
    free(to_hash);
    return 0;
}
EOF

    gcc -O2 /tmp/waf_evasion_encoder.c -o /app/waf_evasion_encoder -lcrypto
    strip /app/waf_evasion_encoder
    rm /tmp/waf_evasion_encoder.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
