#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils rustc cargo
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int is_vowel(char c) {
    return c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u' ||
           c == 'A' || c == 'E' || c == 'I' || c == 'O' || c == 'U';
}

int main() {
    char buffer[4096];
    size_t len = fread(buffer, 1, 4095, stdin);
    buffer[len] = '\0';

    if (len > 0 && buffer[len - 1] == '\n') {
        buffer[len - 1] = '\0';
    }

    char *token = strtok(buffer, ",");
    if (token == NULL) {
        printf("0\n");
        return 0;
    }

    int first = 1;
    while (token != NULL) {
        int token_len = strlen(token);
        int vowels = 0;
        for (int i = 0; i < token_len; i++) {
            if (is_vowel(token[i])) {
                vowels++;
            }
        }

        int val = (token_len * 7 + vowels * 3) % 256;
        if (!first) {
            printf(" ");
        }
        printf("%d", val);
        first = 0;

        token = strtok(NULL, ",");
    }
    printf("\n");
    return 0;
}
EOF

    gcc -O2 /tmp/oracle.c -o /app/dataset_encoder
    strip /app/dataset_encoder
    chmod +x /app/dataset_encoder

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
