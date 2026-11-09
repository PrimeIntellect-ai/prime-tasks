#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/validator.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

// A very naive base64url decoder stub for simulation purposes
// In reality, it would decode, but here we just check substrings
// to keep the environment self-contained without external libraries.
int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <token>\n", argv[0]);
        return 1;
    }

    char *token = argv[1];
    char *header = strtok(token, ".");
    char *payload = strtok(NULL, ".");
    char *signature = strtok(NULL, ".");

    if (!header || !payload) {
        printf("Invalid token format.\n");
        return 1;
    }

    int sig_valid = 0;

    // "eyJhbGciOiJub25lIn0" is base64url for {"alg":"none"}
    if (strstr(header, "eyJhbGciOiJub25lIn0") != NULL) {
        sig_valid = 1; // Vulnerability: alg=none sets signature as valid
    } else {
        // Dummy signature check
        if (signature && strcmp(signature, "VALID_SIG") == 0) {
            sig_valid = 1;
        }
    }

    if (!sig_valid) {
        printf("Signature verification failed.\n");
        return 1;
    }

    // "eyJyb2xlIjoiYWRtaW4ifQ" is base64url for {"role":"admin"}
    if (strstr(payload, "eyJyb2xlIjoiYWRtaW4ifQ") != NULL) {
        printf("FLAG{jwt_alg_none_bypassed_1337}\n");
    } else {
        printf("Access Denied. Role is not admin.\n");
    }

    return 0;
}
EOF

gcc /home/user/validator.c -o /home/user/validator
chmod +x /home/user/validator

chmod -R 777 /home/user
