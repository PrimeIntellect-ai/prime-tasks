#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app/corpus/evil /app/corpus/clean

    # Create the exfil_tool C source
    cat << 'EOF' > /app/exfil.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char b64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

char *base64_encode(const unsigned char *src, size_t len) {
    char *out = malloc(4 * ((len + 2) / 3) + 1);
    char *p = out;
    for (size_t i = 0; i < len; i += 3) {
        int val = src[i] << 16;
        if (i + 1 < len) val |= src[i+1] << 8;
        if (i + 2 < len) val |= src[i+2];
        *p++ = b64_table[(val >> 18) & 0x3F];
        *p++ = b64_table[(val >> 12) & 0x3F];
        *p++ = (i + 1 < len) ? b64_table[(val >> 6) & 0x3F] : '=';
        *p++ = (i + 2 < len) ? b64_table[val & 0x3F] : '=';
    }
    *p = '\0';
    return out;
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *input = argv[1];
    int len = strlen(input);
    unsigned char key[] = {0x4B, 0x1D, 0xEC, 0xAF};
    unsigned char *obf = malloc(len);
    for(int i=0; i<len; i++) {
        obf[i] = input[i] ^ key[i % 4];
    }
    char *b64 = base64_encode(obf, len);
    printf("{\"csp-report\": {\"violated-directive\": \"exfil-%s\"}}\n", b64);
    free(obf);
    free(b64);
    return 0;
}
EOF

    # Compile and strip the binary
    gcc -O2 -s -o /app/exfil_tool /app/exfil.c
    rm /app/exfil.c

    # Generate corpora
    cat << 'EOF' > /app/generate_corpus.py
import os
import json
import base64

def encode(text):
    key = [0x4B, 0x1D, 0xEC, 0xAF]
    obf = bytes([c ^ key[i % 4] for i, c in enumerate(text.encode())])
    return base64.b64encode(obf).decode()

# Evil corpus
for i in range(50):
    payload = f"-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC...{i}"
    b64 = encode(payload)
    with open(f'/app/corpus/evil/log_{i}.json', 'w') as f:
        json.dump({"csp-report": {"document-uri": "http://example.com", "violated-directive": f"exfil-{b64}"}}, f)

# Clean corpus - standard CSP
for i in range(25):
    with open(f'/app/corpus/clean/log_std_{i}.json', 'w') as f:
        json.dump({"csp-report": {"document-uri": "http://example.com", "violated-directive": "default-src 'self'"}}, f)

# Clean corpus - decoy exfil
for i in range(25):
    payload = f"Just a harmless decoy message, no keys here! {i}"
    b64 = encode(payload)
    with open(f'/app/corpus/clean/log_decoy_{i}.json', 'w') as f:
        json.dump({"csp-report": {"document-uri": "http://example.com", "violated-directive": f"exfil-{b64}"}}, f)
EOF

    python3 /app/generate_corpus.py
    rm /app/generate_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
