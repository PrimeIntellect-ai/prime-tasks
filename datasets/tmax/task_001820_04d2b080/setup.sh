#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc imagemagick fonts-liberation
    pip3 install pytest

    mkdir -p /app /oracle

    # Create legacy C source
    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>

static const char b64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

void base64_encode(const unsigned char *src, size_t len, char *out) {
    int i = 0, j = 0;
    for (i = 0; i < len;) {
        uint32_t octet_a = i < len ? src[i++] : 0;
        uint32_t octet_b = i < len ? src[i++] : 0;
        uint32_t octet_c = i < len ? src[i++] : 0;
        uint32_t triple = (octet_a << 0x10) + (octet_b << 0x08) + octet_c;
        out[j++] = b64_table[(triple >> 3 * 6) & 0x3F];
        out[j++] = b64_table[(triple >> 2 * 6) & 0x3F];
        out[j++] = b64_table[(triple >> 1 * 6) & 0x3F];
        out[j++] = b64_table[(triple >> 0 * 6) & 0x3F];
    }
    for (int k = 0; k < (3 - len % 3) % 3; k++) out[j - 1 - k] = '=';
    out[j] = '\0';
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    size_t len = strlen(argv[1]);
    unsigned char *buf = malloc(len);
    for (size_t i = 0; i < len; i++) {
        buf[i] = argv[1][i] ^ 0x33;
    }
    char *out = malloc(len * 2 + 5);
    base64_encode(buf, len, out);
    printf("%s\n", out);
    free(buf);
    free(out);
    return 0;
}
EOF

    # Create oracle C source
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>

static const char b64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

void base64_encode(const unsigned char *src, size_t len, char *out) {
    int i = 0, j = 0;
    for (i = 0; i < len;) {
        uint32_t octet_a = i < len ? src[i++] : 0;
        uint32_t octet_b = i < len ? src[i++] : 0;
        uint32_t octet_c = i < len ? src[i++] : 0;
        uint32_t triple = (octet_a << 0x10) + (octet_b << 0x08) + octet_c;
        out[j++] = b64_table[(triple >> 3 * 6) & 0x3F];
        out[j++] = b64_table[(triple >> 2 * 6) & 0x3F];
        out[j++] = b64_table[(triple >> 1 * 6) & 0x3F];
        out[j++] = b64_table[(triple >> 0 * 6) & 0x3F];
    }
    for (int k = 0; k < (3 - len % 3) % 3; k++) out[j - 1 - k] = '=';
    out[j] = '\0';
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    const char *prefix = "SECURE|";
    size_t plen = strlen(prefix);
    size_t alen = strlen(argv[1]);
    size_t len = plen + alen;
    unsigned char *buf = malloc(len);
    memcpy(buf, prefix, plen);
    memcpy(buf + plen, argv[1], alen);
    for (size_t i = 0; i < len; i++) {
        buf[i] = buf[i] ^ 0x5A;
    }
    char *out = malloc(len * 2 + 5);
    base64_encode(buf, len, out);
    printf("%s\n", out);
    free(buf);
    free(out);
    return 0;
}
EOF

    # Compile and strip binaries
    gcc -O2 /tmp/legacy.c -o /app/token_legacy
    strip /app/token_legacy
    gcc -O2 /tmp/oracle.c -o /oracle/token_v2_oracle
    strip /oracle/token_v2_oracle

    # Generate image
    # Adjust ImageMagick policy to allow text rendering if needed
    sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/g' /etc/ImageMagick-6/policy.xml || true
    convert -size 600x200 xc:white -fill black -pointsize 24 -annotate +20+50 "V2 Update: Prepend 'SECURE|' to the input.\nChange XOR key to 0x5A." /app/update_notes.png

    # Cleanup
    rm /tmp/legacy.c /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
