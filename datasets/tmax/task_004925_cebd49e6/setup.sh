#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the C source for the legacy auth binary
    cat << 'EOF' > /home/user/legacy_auth.c
#include <stdio.h>
#include <string.h>

const char* secret_key_data = "XOR_KEY=C0mpL1@n"; // The 8-byte key is "C0mpL1@n"

int main() {
    printf("Legacy auth module loaded.\n");
    return 0;
}
EOF

    # Compile the binary and remove the source
    gcc /home/user/legacy_auth.c -o /home/user/legacy_auth
    rm /home/user/legacy_auth.c

    # Create the tokens file
    cat << 'EOF' > /home/user/tokens.txt
SGVsbG8xMjM=
QWRtaW5QYXNz
U3VwZXJTZWNyZXQ=
EOF

    chmod -R 777 /home/user
