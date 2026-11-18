#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/workspace/uploads

    cat << 'EOF' > /home/user/workspace/uploader.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void decrypt(unsigned char *data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        data[i] ^= 0x5A; // Simple XOR cipher
    }
}

// Insecure path traversal protection
void sanitize(char *filename) {
    char *pos;
    while ((pos = strstr(filename, "../")) != NULL) {
        memmove(pos, pos + 3, strlen(pos + 3) + 1);
        break; // BUG: Only removes the first occurrence
    }
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <bundle.bin>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    size_t size = ftell(f);
    fseek(f, 0, SEEK_SET);

    unsigned char *buffer = malloc(size);
    fread(buffer, 1, size, f);
    fclose(f);

    decrypt(buffer, size);

    unsigned char name_len = buffer[0];
    char filename[256] = {0};
    memcpy(filename, buffer + 1, name_len);

    sanitize(filename);

    char filepath[512];
    snprintf(filepath, sizeof(filepath), "./uploads/%s", filename);

    FILE *out = fopen(filepath, "wb");
    if (out) {
        fwrite(buffer + 1 + name_len, 1, size - 1 - name_len, out);
        fclose(out);
        printf("File saved to %s\n", filepath);
    } else {
        printf("Failed to save file.\n");
    }

    free(buffer);
    return 0;
}
EOF

    cd /home/user/workspace
    gcc uploader.c -o uploader

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
