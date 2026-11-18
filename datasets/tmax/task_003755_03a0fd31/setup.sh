#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/audit_service.c
#include <stdio.h>
#include <string.h>

const char* XOR_KEY = "C0mpL1@nc3";

void log_query(const char* query) {
    // Dummy function that would normally encrypt and write to log
    // The key is present in the .rodata section for reverse engineering
    printf("Logging with key: %s\n", XOR_KEY);
}

int main() {
    log_query("dummy");
    return 0;
}
EOF

    gcc /home/user/audit_service.c -o /home/user/audit_service
    rm /home/user/audit_service.c

    cat << 'EOF' > /home/user/generate_log.py
key = b"C0mpL1@nc3"
plaintext = b"""[INFO] User login: jsmith
[INFO] Query: SELECT * FROM users WHERE username = 'jsmith'
[WARN] Failed login: admin
[WARN] Query: SELECT * FROM users WHERE username = 'admin' OR '1'='1' --'
[INFO] User logout: jsmith
"""

ciphertext = bytearray()
for i, byte in enumerate(plaintext):
    ciphertext.append(byte ^ key[i % len(key)])

with open("/home/user/encrypted_log.bin", "wb") as f:
    f.write(ciphertext)
EOF

    python3 /home/user/generate_log.py
    rm /home/user/generate_log.py

    chmod -R 777 /home/user
