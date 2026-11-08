#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/auth_policy.cpp
#include <iostream>
#include <cstring>

// Legacy policy: custom encoding via XOR and decrement
void decode_token(const unsigned char* input, int len, char* output) {
    for(int i = 0; i < len; i++) {
        output[i] = (char)(((input[i] + 1) ^ 0x5A) & 0xFF);
    }
    output[len] = '\0';
}

void process_auth(const unsigned char* encoded_payload, int payload_len) {
    char admin_role_flag = 0;
    char local_buffer[16];
    char decoded[256];

    decode_token(encoded_payload, payload_len, decoded);

    // VULNERABILITY: Classic buffer overflow leading to privesc
    strcpy(local_buffer, decoded);

    if (admin_role_flag != 0) {
        std::cout << "Elevated Privileges Granted!\n";
    }
}
EOF

    python3 -c '
pt = b"ELEVATE_TO_SYSTEM_R00T"
# To encode: input[i] = ((pt[i] ^ 0x5A) - 1) & 0xFF
ct = bytes([((c ^ 0x5A) - 1) & 0xFF for c in pt])
with open("/home/user/payload.bin", "wb") as f:
    f.write(ct)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
