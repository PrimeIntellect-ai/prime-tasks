#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb libc6-dev
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/log_auditor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <regex.h>

void process_payload(const char* hex_in, char* hex_out) {
    int len = strlen(hex_in);
    int byte_len = len / 2;
    unsigned char* bytes = malloc(byte_len + 1);

    for (int i = 0; i < byte_len; i++) {
        sscanf(hex_in + 2*i, "%2hhx", &bytes[i]);
    }

    unsigned char S = 0x5A;
    for (int i = 0; i < byte_len; i++) {
        S = (S * 31 + 17) & 0xFF;
        bytes[i] ^= S;
    }
    bytes[byte_len] = '\0';

    regex_t regex;
    regcomp(&regex, "\\b[0-9]{3}-[0-9]{2}-[0-9]{4}\\b", REG_EXTENDED);
    regmatch_t pmatch[1];

    char* current = (char*)bytes;
    while (regexec(&regex, current, 1, pmatch, 0) == 0) {
        for (int i = 0; i < 11; i++) {
            if (current[pmatch[0].rm_so + i] != '-') {
                current[pmatch[0].rm_so + i] = '*';
            }
        }
        current += pmatch[0].rm_eo;
    }
    regfree(&regex);

    S = 0x5A;
    for (int i = 0; i < byte_len; i++) {
        S = (S * 31 + 17) & 0xFF;
        bytes[i] ^= S;
    }

    for (int i = 0; i < byte_len; i++) {
        sprintf(hex_out + 2*i, "%02x", bytes[i]);
    }
    free(bytes);
}

int main() {
    char line[4096];
    if (!fgets(line, sizeof(line), stdin)) return 0;

    char* newline = strchr(line, '\n');
    if (newline) *newline = '\0';

    char* sep = strstr(line, " | ");
    if (!sep) return 1;

    *sep = '\0';
    char* csp_part = line;
    char* payload_part = sep + 3;

    if (strncmp(csp_part, "CSP: ", 5) != 0) return 1;
    if (strncmp(payload_part, "PAYLOAD: ", 9) != 0) return 1;

    char csp[4096];
    strcpy(csp, csp_part + 5);

    if (!strstr(csp, "script-src 'self'")) {
        strcat(csp, "; script-src 'self'");
    }

    char hex_in[4096];
    strcpy(hex_in, payload_part + 9);

    char hex_out[4096] = {0};
    process_payload(hex_in, hex_out);

    printf("CSP: %s | PAYLOAD: %s\n", csp, hex_out);
    return 0;
}
EOF

    gcc -o /app/log_auditor /tmp/log_auditor.c -s
    chmod +x /app/log_auditor
    rm /tmp/log_auditor.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
