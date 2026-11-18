#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/urls.txt
/api/v1/process?action=start&payload=Hello%20World
/api/v1/log?payload=This%20is%20a%20very%20long%20string%20that%20will%20overflow%20the%20thirty%20two%20byte%20buffer
/api/v2/update?id=99&payload=Secret%2BData%2521
EOF

    cat << 'EOF' > /home/user/decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char* decode_url_payload(const char* src) {
    // BUG: Fixed size buffer causes overflow.
    char buffer[32]; 
    int i = 0, j = 0;
    while (src[i] != '\0') {
        if (src[i] == '%' && src[i+1] != '\0' && src[i+2] != '\0') {
            char hex[3] = {src[i+1], src[i+2], '\0'};
            buffer[j++] = (char)strtol(hex, NULL, 16);
            i += 3;
        } else if (src[i] == '+') {
            buffer[j++] = ' ';
            i++;
        } else {
            buffer[j++] = src[i++];
        }
    }
    buffer[j] = '\0';

    char* ret = malloc(j + 1);
    strcpy(ret, buffer);
    return ret;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
