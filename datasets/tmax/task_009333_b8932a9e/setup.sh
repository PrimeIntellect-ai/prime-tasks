#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_server.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <token>\n", argv[0]);
        return 1;
    }

    char *token = argv[1];

    // Simulate parsing the token. eyJhbGciOiJub25lIn0 is base64url for {"alg":"none"}
    if (strstr(token, "eyJhbGciOiJub25lIn0") != NULL) {
        // VULNERABILITY: Bypassing signature check if alg is none
        printf("ACCEPTED: SIGNATURE_BYPASSED\n");
        return 0;
    }

    // Simulate valid signature check
    if (strstr(token, ".VALID_SIG") != NULL) {
        printf("ACCEPTED: VALID_SIGNATURE\n");
        return 0;
    }

    printf("REJECTED: INVALID_SIGNATURE\n");
    return 1;
}
EOF

    cat << 'EOF' > /home/user/tokens.txt
TKN-01:eyJhbGciOiJIUzI1NiJ9.payload.VALID_SIG
TKN-02:eyJhbGciOiJIUzI1NiJ9.payload.INVALID_SIG
TKN-03:eyJhbGciOiJub25lIn0.malicious_payload.
TKN-04:eyJhbGciOiJIUzI1NiJ9.admin_payload.VALID_SIG
EOF

    chmod -R 777 /home/user
