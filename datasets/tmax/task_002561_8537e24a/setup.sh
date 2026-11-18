#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc openssl
pip3 install pytest

mkdir -p /home/user

# 1. Create the vulnerable C program
cat << 'EOF' > /home/user/validator.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void hex_to_ascii(const char* hex, char* ascii) {
    size_t len = strlen(hex);
    for (size_t i = 0; i < len; i += 2) {
        sscanf(hex + i, "%2hhx", &ascii[i / 2]);
    }
    ascii[len / 2] = '\0';
}

void xor_decrypt(char* data, size_t len, char key) {
    for (size_t i = 0; i < len; i++) {
        data[i] ^= key;
    }
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <token>\n", argv[0]);
        return 1;
    }

    char *token = strdup(argv[1]);
    char *header_hex = strtok(token, ".");
    char *payload_hex = strtok(NULL, ".");
    char *sig_hex = strtok(NULL, ".");

    if (!header_hex || !payload_hex || !sig_hex) {
        printf("Invalid token format.\n");
        return 1;
    }

    char header[256] = {0};
    char payload[256] = {0};

    hex_to_ascii(header_hex, header);
    hex_to_ascii(payload_hex, payload);

    // Decrypt payload with hardcoded XOR key 0x5A
    xor_decrypt(payload, strlen(payload_hex)/2, 0x5A);

    // Vulnerability: if header contains "alg":"none", skip signature check
    int skip_sig = 0;
    if (strstr(header, "\"alg\":\"none\"") != NULL) {
        skip_sig = 1;
    }

    if (!skip_sig) {
        // Dummy strict signature check for simulation
        if (strcmp(sig_hex, "deadbeef") != 0) {
            printf("Signature verification failed!\n");
            return 1;
        }
    }

    if (strstr(payload, "\"role\":\"admin\"") != NULL) {
        printf("Access Granted: Admin\n");
        return 0;
    } else {
        printf("Access Granted: User\n");
        return 0;
    }
}
EOF

# 2. Create the checksum file
sha256sum /home/user/validator.c > /home/user/checksum.sha256

# 3. Generate mock certificates
openssl req -x509 -newkey rsa:2048 -keyout /tmp/ca.key -out /home/user/ca.crt -days 365 -nodes -subj "/CN=FakeCA" 2>/dev/null
openssl req -newkey rsa:2048 -keyout /tmp/server.key -out /tmp/server.csr -nodes -subj "/CN=FakeServer" 2>/dev/null
openssl x509 -req -in /tmp/server.csr -CA /home/user/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /home/user/server.crt -days 365 2>/dev/null

# Clean up temp files
rm -f /tmp/ca.key /tmp/server.key /tmp/server.csr /home/user/ca.srl

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
