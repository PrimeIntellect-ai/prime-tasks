#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy_tokenizer.c
#include <stdio.h>
#include <ctype.h>
#include <string.h>

int main() {
    char buffer[1024];
    if (fgets(buffer, sizeof(buffer), stdin) != NULL) {
        for (int i = 0; buffer[i]; i++) {
            buffer[i] = tolower((unsigned char)buffer[i]);
        }
        char *p = buffer;
        int first = 1;
        while (*p) {
            if (isalpha((unsigned char)*p) || isdigit((unsigned char)*p)) {
                if (!first) putchar(' ');
                first = 0;
                while (isalpha((unsigned char)*p) || isdigit((unsigned char)*p)) {
                    putchar(*p);
                    p++;
                }
            } else {
                p++;
            }
        }
        printf("\n");
    }
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_tokenizer.c -o /app/legacy_tokenizer
    strip /app/legacy_tokenizer
    chmod +x /app/legacy_tokenizer
    rm /tmp/legacy_tokenizer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
