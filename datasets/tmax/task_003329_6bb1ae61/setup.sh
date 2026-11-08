#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app/certs
    cat << 'EOF' > /app/certs/root.pem
-----BEGIN CERTIFICATE-----
MIIB...
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIB...
-----END CERTIFICATE-----
EOF

    cat << 'EOF' > /tmp/priv_checker.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const int b64index[256] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,62,0,0,0,63,
    52,53,54,55,56,57,58,59,60,61,0,0,0,0,0,0,
    0,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,0,0,0,0,0,
    0,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
};

int b64decode(const char *in, unsigned char *out) {
    int len = strlen(in);
    if (len % 4 != 0) return -1;
    for (int i=0; i<len; i++) {
        char c = in[i];
        if (!( (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '+' || c == '/' || c == '=' )) {
            return -1;
        }
    }
    int pad = 0;
    if (len > 0 && in[len-1] == '=') pad++;
    if (len > 1 && in[len-2] == '=') pad++;

    int out_len = (len / 4) * 3 - pad;
    int j = 0;
    for (int i = 0; i < len; i += 4) {
        int n = b64index[(int)in[i]] << 18 | b64index[(int)in[i+1]] << 12 | b64index[(int)in[i+2]] << 6 | b64index[(int)in[i+3]];
        out[j++] = n >> 16;
        if (j < out_len) out[j++] = n >> 8 & 0xFF;
        if (j < out_len) out[j++] = n & 0xFF;
    }
    out[out_len] = '\0';
    return out_len;
}

int is_valid_utf8(const unsigned char *s, int len) {
    int i = 0;
    while (i < len) {
        if (s[i] <= 0x7F) i++;
        else if ((s[i] & 0xE0) == 0xC0) i += 2;
        else if ((s[i] & 0xF0) == 0xE0) i += 3;
        else if ((s[i] & 0xF8) == 0xF0) i += 4;
        else return 0;
        if (i > len) return 0;
    }
    return 1;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "ERROR: Invalid arguments\n");
        return 1;
    }

    int in_len = strlen(argv[1]);
    unsigned char *dec = malloc(in_len + 1);
    int dec_len = b64decode(argv[1], dec);
    if (dec_len < 0) {
        fprintf(stderr, "ERROR: Invalid payload encoding\n");
        return 2;
    }

    if (!is_valid_utf8(dec, dec_len)) {
        fprintf(stderr, "ERROR: Payload decoding failed\n");
        return 3;
    }

    int pipes = 0;
    for (int i = 0; i < dec_len; i++) {
        if (dec[i] == '|') pipes++;
    }
    if (pipes != 2) {
        fprintf(stderr, "ERROR: Invalid format\n");
        return 4;
    }

    char *cert_sn = (char *)dec;
    char *csp = strchr(cert_sn, '|');
    *csp = '\0'; csp++;
    char *priv = strchr(csp, '|');
    *priv = '\0'; priv++;

    FILE *f = fopen("/app/certs/root.pem", "r");
    if (!f) return 5;

    int count = 0;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (strstr(line, "CERTIFICATE")) count++;
    }
    fclose(f);

    if (count == 0) {
        printf("DENIED\n");
        return 0;
    }

    long long sn = atoll(cert_sn);
    if (sn % count != 0) {
        printf("DENIED\n");
        return 0;
    }

    if (strncmp(csp, "default-src 'none'", 18) != 0) {
        printf("DENIED\n");
        return 0;
    }

    if (strcmp(priv, "root") == 0 || strcmp(priv, "admin") == 0) {
        printf("GRANTED: %s\n", priv);
    } else {
        printf("DENIED\n");
    }

    return 0;
}
EOF

    gcc -static -O2 /tmp/priv_checker.c -o /app/priv_checker
    strip -s /app/priv_checker
    chmod +x /app/priv_checker
    rm /tmp/priv_checker.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
