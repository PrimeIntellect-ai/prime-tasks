#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev
    pip3 install pytest flask fastapi uvicorn

    mkdir -p /home/user/extracted_docs
    mkdir -p /app

    cat << 'EOF' > /tmp/doc_indexer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/sha.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    SHA256_CTX sha256;
    SHA256_Init(&sha256);
    unsigned char buffer[4096];
    int bytesRead = 0;
    while ((bytesRead = fread(buffer, 1, 4096, f))) {
        SHA256_Update(&sha256, buffer, bytesRead);
    }
    fclose(f);

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256_Final(hash, &sha256);

    for(int i = 0; i < SHA256_DIGEST_LENGTH; i++) {
        printf("%02x", hash[i] ^ 0x42);
    }

    char *ext = strrchr(argv[1], '.');
    if (ext && strcmp(ext, ".txt") == 0) printf(":text\n");
    else if (ext && strcmp(ext, ".png") == 0) printf(":image\n");
    else printf(":binary\n");

    return 0;
}
EOF

    gcc /tmp/doc_indexer.c -o /app/doc_indexer -lssl -lcrypto -O3
    strip /app/doc_indexer
    chmod +x /app/doc_indexer
    rm /tmp/doc_indexer.c

    cat << 'EOF' > /tmp/make_archive.py
import struct
import os

files = [
    (1, "docs/intro.txt", b"Welcome to the legacy documentation system. This is the intro."),
    (2, "images/diagram.png", b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDRFAKE_IMAGE_DATA"),
    (3, "config/settings.bin", b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09")
]

with open("/home/user/legacy_docs.dcar", "wb") as f:
    f.write(b"DCAR")
    for file_id, path, data in files:
        f.write(struct.pack(">H", file_id))
        f.write(struct.pack(">I", len(data)))
        path_bytes = path.encode('ascii')
        path_padded = path_bytes + b'\x00' * (128 - len(path_bytes))
        f.write(path_padded)
        f.write(data)
EOF

    python3 /tmp/make_archive.py
    rm /tmp/make_archive.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
