#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/inspector
    cd /home/user/inspector

    # 1. Create the AES-256-CBC key (32 bytes)
    echo -n "0123456789abcdef0123456789abcdef" > key.bin

    # 2. Create the plaintext traffic (with a long header to trigger the overflow)
    cat << 'EOF' > traffic.txt
HTTP/1.1 200 OK
Server: LegacyProxy/1.0
X-Custom-Very-Long-Header-That-Will-Cause-A-Buffer-Overflow-If-Copied-Using-Strcpy-Because-It-Is-Way-Longer-Than-Sixty-Four-Bytes-And-Will-Smash-The-Stack: true
Content-Type: text/html

<html><body>Secret payload!</body></html>
EOF

    # 3. Encrypt the traffic using OpenSSL
    openssl enc -aes-256-cbc -in traffic.txt -out traffic.enc -K 3031323334353637383961626364656630313233343536373839616263646566 -iv 00000000000000000000000000000000
    rm traffic.txt

    # 4. Create the vulnerable C code
    cat << 'EOF' > traffic_inspector.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/evp.h>

void parse_request(const char *req) {
    char buffer[64];
    // VULNERABILITY: Stack-based buffer overflow
    strcpy(buffer, req);
    printf("Parsed Request Info: %s\n", buffer);
}

int main() {
    FILE *f_in = fopen("traffic.enc", "rb");
    FILE *f_key = fopen("key.bin", "rb");
    FILE *f_out = fopen("decrypted_log.txt", "w");

    if (!f_in || !f_key || !f_out) {
        printf("Error opening files.\n");
        return 1;
    }

    unsigned char key[32];
    fread(key, 1, 32, f_key);
    fclose(f_key);

    unsigned char iv[16] = {0}; // Static IV for simplicity

    fseek(f_in, 0, SEEK_END);
    long enc_len = ftell(f_in);
    fseek(f_in, 0, SEEK_SET);

    unsigned char *enc_data = malloc(enc_len);
    fread(enc_data, 1, enc_len, f_in);
    fclose(f_in);

    unsigned char *dec_data = malloc(enc_len + EVP_MAX_BLOCK_LENGTH);
    int dec_len, tmplen;

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    EVP_DecryptInit_ex(ctx, EVP_aes_256_cbc(), NULL, key, iv);
    EVP_DecryptUpdate(ctx, dec_data, &dec_len, enc_data, enc_len);
    EVP_DecryptFinal_ex(ctx, dec_data + dec_len, &tmplen);
    dec_len += tmplen;
    EVP_CIPHER_CTX_free(ctx);

    dec_data[dec_len] = '\0';

    // Simulate parsing the first header line to trigger vulnerability
    char first_line[256];
    sscanf((char*)dec_data, "%255[^\n]", first_line);
    parse_request(first_line);

    // OUTPUT WRITING
    // TODO: Inject Content-Security-Policy header after HTTP/1.1 200 OK
    // Currently, it just prints the raw decrypted data.
    fprintf(f_out, "%s", dec_data);

    fclose(f_out);
    free(enc_data);
    free(dec_data);
    return 0;
}
EOF

    chown -R user:user /home/user/inspector
    chmod -R 777 /home/user
