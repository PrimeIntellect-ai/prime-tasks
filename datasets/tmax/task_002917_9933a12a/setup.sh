#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc expect e2fsprogs openssh-client openssh-server
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_sensor_bin.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void base64_encode(const unsigned char *src, size_t len, char *out) {
    const char base64_chars[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t i = 0, j = 0;
    unsigned char char_array_3[3];
    unsigned char char_array_4[4];

    while (len--) {
        char_array_3[i++] = *(src++);
        if (i == 3) {
            char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
            char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
            char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);
            char_array_4[3] = char_array_3[2] & 0x3f;
            for(i = 0; (i < 4) ; i++) out[j++] = base64_chars[char_array_4[i]];
            i = 0;
        }
    }

    if (i) {
        for(size_t k = i; k < 3; k++) char_array_3[k] = '\0';
        char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
        char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
        char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);
        char_array_4[3] = char_array_3[2] & 0x3f;
        for (size_t k = 0; (k < i + 1); k++) out[j++] = base64_chars[char_array_4[k]];
        while((i++ < 3)) out[j++] = '=';
    }
    out[j] = '\0';
}

int main(int argc, char *argv[]) {
    if (argc > 1 && strcmp(argv[1], "--setup") == 0) {
        char buf[256];
        printf("Initialize sensor storage? (yes/no): ");
        fflush(stdout);
        if (!fgets(buf, sizeof(buf), stdin)) return 1;
        printf("Enter Site ID: ");
        fflush(stdout);
        if (!fgets(buf, sizeof(buf), stdin)) return 1;
        printf("Setup complete.\n");
        return 0;
    }

    char line[4096];
    if (!fgets(line, sizeof(line), stdin)) return 1;
    size_t len = strlen(line);
    if (len > 0 && line[len-1] == '\n') {
        line[len-1] = '\0';
        len--;
    }

    char reversed[4096];
    for (size_t i = 0; i < len; i++) {
        reversed[i] = line[len - 1 - i];
    }
    reversed[len] = '\0';

    char b64[8192];
    base64_encode((const unsigned char *)reversed, len, b64);
    printf("%s\n", b64);
    return 0;
}
EOF
    gcc -O2 /app/legacy_sensor_bin.c -o /app/legacy_sensor_bin
    strip /app/legacy_sensor_bin
    rm /app/legacy_sensor_bin.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
