#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/evidence

    cat << 'EOF' > /home/user/evidence/headers.txt
POST /api/exfil HTTP/1.1
Host: 10.10.10.99
User-Agent: Mozilla/5.0
Cookie: SessionID=30920; Tracking=XYZ
Content-Type: application/octet-stream
Content-Length: 64
EOF

    python3 -c '
key = 213
plaintext = b"C2_SERVER: evil-corp.local\nTARGET_CC: 4532111122223333\nSTATUS: ACTIVE\n"
ciphertext = bytes([b ^ key for b in plaintext])
with open("/home/user/evidence/payload.bin", "wb") as f:
    f.write(ciphertext)
'

    cat << 'EOF' > /home/user/evidence/decryptor_template.c
#include <stdio.h>
#include <stdlib.h>

// The SessionID is generated from a 4-digit PIN (0000 - 9999)
// int session_id = (pin ^ 0x5A5A) + 12345;

int main() {
    int target_session_id = 0; // TODO: Extract from headers.txt
    int found_pin = -1;

    // TODO: Brute-force the 4-digit PIN (0000-9999) to match target_session_id

    // printf("Found PIN: %04d\n", found_pin);

    // TODO: Read /home/user/evidence/payload.bin
    // TODO: XOR each byte with (found_pin % 256)
    // TODO: Write decrypted bytes to /home/user/decrypted.txt

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
