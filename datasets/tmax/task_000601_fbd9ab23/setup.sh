#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc rustc cargo binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/log_packer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char *input = NULL;
    size_t len = 0;

    char buf[4096];
    size_t bytes;
    while ((bytes = fread(buf, 1, sizeof(buf), stdin)) > 0) {
        input = realloc(input, len + bytes + 1);
        memcpy(input + len, buf, bytes);
        len += bytes;
        input[len] = '\0';
    }

    if (len == 0) return 0;

    char *prev = NULL;
    size_t prev_len = 0;

    char *curr = input;
    char *delim;

    while ((delim = strstr(curr, "===\n")) != NULL) {
        size_t curr_len = delim - curr;

        size_t l = 0;
        while (l < curr_len && l < prev_len && curr[l] == prev[l]) {
            l++;
        }

        unsigned short l_out = (unsigned short)l;
        fwrite(&l_out, 1, 2, stdout);
        fwrite(curr + l, 1, curr_len - l, stdout);
        fputc(0x00, stdout);

        prev = curr;
        prev_len = curr_len;

        curr = delim + 4;
    }

    free(input);
    return 0;
}
EOF

    gcc -O2 /tmp/log_packer.c -o /app/log_packer
    strip /app/log_packer
    rm /tmp/log_packer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
