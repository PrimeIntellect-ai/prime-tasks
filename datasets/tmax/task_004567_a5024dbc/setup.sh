#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        binutils \
        gdb \
        libc-dev

    pip3 install pytest

    mkdir -p /app

    # Create the C source code for the waf_auth_filter
    cat << 'EOF' > /app/waf_auth_filter.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static const int b64index[256] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,62,63,62,62,63,
    52,53,54,55,56,57,58,59,60,61,0,0,0,0,0,0,
    0,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,
    15,16,17,18,19,20,21,22,23,24,25,0,0,0,0,63,
    0,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,
    41,42,43,44,45,46,47,48,49,50,51
};

size_t b64_decode(const char *in, unsigned char **out) {
    size_t len = strlen(in);
    if (len == 0) return (size_t)-1;
    int pad = 0;
    if (len > 0 && in[len-1] == '=') pad++;
    if (len > 1 && in[len-2] == '=') pad++;
    size_t out_len = (len * 3) / 4 - pad;
    *out = malloc(out_len);
    if (!*out) return (size_t)-1;
    size_t j = 0;
    for (size_t i = 0; i < len; i += 4) {
        int n = b64index[(unsigned char)in[i]] << 18 |
                b64index[(unsigned char)in[i+1]] << 12 |
                (i+2 < len && in[i+2] != '=' ? b64index[(unsigned char)in[i+2]] << 6 : 0) |
                (i+3 < len && in[i+3] != '=' ? b64index[(unsigned char)in[i+3]] : 0);
        if (j < out_len) (*out)[j++] = n >> 16;
        if (j < out_len) (*out)[j++] = (n >> 8) & 0xFF;
        if (j < out_len) (*out)[j++] = n & 0xFF;
    }
    return out_len;
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    unsigned char *decoded = NULL;
    size_t len = b64_decode(argv[1], &decoded);
    if (len == (size_t)-1 || len < 4) {
        printf("INVALID\n");
        if (decoded) free(decoded);
        return 1;
    }

    if (decoded[0] != 0xCA || decoded[1] != 0xFE) {
        printf("INVALID\n");
        free(decoded);
        return 1;
    }

    uint8_t p_len = decoded[2];
    if (len != (size_t)(4 + p_len)) {
        printf("INVALID\n");
        free(decoded);
        return 1;
    }

    uint8_t chk = 0x5A;
    for (size_t i = 0; i < len - 1; i++) {
        chk ^= decoded[i];
    }

    if (chk != decoded[len - 1]) {
        printf("INVALID\n");
        free(decoded);
        return 1;
    }

    for (size_t i = 0; i < p_len; i++) {
        putchar(decoded[3 + i] ^ ((i + 0x42) & 0xFF));
    }

    free(decoded);
    return 0;
}
EOF

    # Compile and strip the binary
    gcc -O2 -o /app/waf_auth_filter /app/waf_auth_filter.c
    strip /app/waf_auth_filter
    rm /app/waf_auth_filter.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
