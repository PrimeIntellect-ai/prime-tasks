#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb strace ltrace file xxd
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/bin
cat << 'EOF' > /home/user/bin/rotator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Simple base64 decode for demonstration (standard b64, not robust)
const char b64chars[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
void decode_b64(const char *in, char *out) {
    int i = 0, j = 0;
    while (in[i] && in[i] != '.') {
        char *p1 = strchr(b64chars, in[i]);
        char *p2 = strchr(b64chars, in[i+1]);
        char *p3 = strchr(b64chars, in[i+2]);
        char *p4 = strchr(b64chars, in[i+3]);

        int n1 = p1 ? p1 - b64chars : 0;
        int n2 = p2 ? p2 - b64chars : 0;
        int n3 = p3 ? p3 - b64chars : 0;
        int n4 = p4 ? p4 - b64chars : 0;

        out[j++] = (n1 << 2) | ((n2 & 0x30) >> 4);
        if (p3) out[j++] = ((n2 & 0x0f) << 4) | ((n3 & 0x3c) >> 2);
        if (p4) out[j++] = ((n3 & 0x03) << 6) | n4;

        i += 4;
    }
    out[j] = '\0';
}

int main() {
    FILE *f = fopen("/home/user/token.txt", "r");
    if (!f) {
        printf("Error: Could not open /home/user/token.txt\n");
        return 1;
    }

    char token[1024] = {0};
    fread(token, 1, 1023, f);
    fclose(f);

    char *header_b64 = strtok(token, ".");
    char *payload_b64 = strtok(NULL, ".");
    char *signature = strtok(NULL, ".");

    if (!header_b64 || !payload_b64 || !signature) {
        printf("Invalid token format.\n");
        return 1;
    }

    char header[512] = {0};
    char payload[512] = {0};

    decode_b64(header_b64, header);
    decode_b64(payload_b64, payload);

    int is_valid = 0;
    if (strstr(header, "\"alg\":\"none\"") || strstr(header, "\"alg\": \"none\"")) {
        is_valid = 1;
    } else {
        // Dummy signature check that always fails without the key
        if (strcmp(signature, "VALID_SIG_WITH_UNKNOWN_KEY") == 0) {
            is_valid = 1;
        }
    }

    if (!is_valid) {
        printf("Signature validation failed!\n");
        return 1;
    }

    // Parse payload manually: {"role":"admin","new_password":"..."}
    if (strstr(payload, "\"role\":\"admin\"") || strstr(payload, "\"role\": \"admin\"")) {
        char *pw_start = strstr(payload, "new_password\":\"");
        if (pw_start) {
            pw_start += 15;
            char *pw_end = strchr(pw_start, '"');
            if (pw_end) {
                *pw_end = '\0';
                FILE *out = fopen("/home/user/rotated_password.log", "w");
                if (out) {
                    fprintf(out, "admin:%s\n", pw_start);
                    fclose(out);
                    printf("Password successfully rotated.\n");
                    return 0;
                }
            }
        }
    }
    printf("Invalid payload or unauthorized role.\n");
    return 1;
}
EOF

gcc /home/user/bin/rotator.c -o /home/user/bin/rotator
strip /home/user/bin/rotator
rm /home/user/bin/rotator.c

chmod -R 777 /home/user
