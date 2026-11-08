#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create reference implementation
    cat << 'EOF' > /app/legacy_sanitizer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int hex_value(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

int main() {
    size_t cap = 1024;
    size_t len = 0;
    char *buf = malloc(cap);
    if (!buf) return 1;
    int c;
    while ((c = getchar()) != EOF) {
        if (len + 1 >= cap) { 
            cap *= 2; 
            char *new_buf = realloc(buf, cap);
            if (!new_buf) { free(buf); return 1; }
            buf = new_buf;
        }
        buf[len++] = c;
    }
    buf[len] = '\0';

    size_t w = 0;
    for (size_t r = 0; r < len; ) {
        if (buf[r] == '%' && r + 2 < len) {
            int h1 = hex_value(buf[r+1]);
            int h2 = hex_value(buf[r+2]);
            if (h1 != -1 && h2 != -1) {
                buf[w++] = (h1 << 4) | h2;
                r += 3;
                continue;
            }
        }
        buf[w++] = buf[r++];
    }
    len = w;
    buf[len] = '\0';

    char *p;
    while ((p = strstr(buf, "<script>")) != NULL) {
        size_t rem = len - ((p - buf) + 8);
        memmove(p, p + 8, rem + 1);
        len -= 8;
    }

    fwrite(buf, 1, len, stdout);
    free(buf);
    return 0;
}
EOF

    gcc -O2 /app/legacy_sanitizer.c -o /app/legacy_sanitizer
    strip /app/legacy_sanitizer
    rm /app/legacy_sanitizer.c

    # Create buggy draft
    cat << 'EOF' > /home/user/sanitizer_draft.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int hex_value(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

int main() {
    char buf[8192];
    size_t len = fread(buf, 1, sizeof(buf)-1, stdin);
    buf[len] = '\0';

    char out[8192];
    size_t w = 0;
    for (size_t r = 0; r < len; r++) {
        if (buf[r] == '%') {
            int h1 = hex_value(buf[r+1]);
            int h2 = hex_value(buf[r+2]);
            out[w++] = (h1 << 4) | h2;
            r += 2;
        } else {
            out[w++] = buf[r];
        }
    }
    out[w] = '\0';

    char *p = strstr(out, "<script>");
    if (p) {
        memmove(p, p + 8, strlen(p + 8) + 1);
    }

    printf("%s", out);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
