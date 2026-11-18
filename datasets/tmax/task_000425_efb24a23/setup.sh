#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssl binutils xxd
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # 1. Generate a dummy certificate
    openssl req -x509 -newkey rsa:2048 -keyout dummy.key -out dummy.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=malicious-c2.local" 2>/dev/null

    # 2. Encrypt the certificate with XOR key 0x4B (75)
    python3 -c "
with open('dummy.crt', 'rb') as f:
    data = f.read()
enc = bytes([b ^ 0x4B for b in data])
with open('cert.enc', 'wb') as f:
    f.write(enc)
"

    # 3. Create the C source for the ELF binary
    cat << 'EOF' > scanner.c
#include <stdio.h>
__attribute__((section(".secret_key"))) unsigned char hidden_key = 0x4B;

int main() {
    printf("Scanner initialized.\n");
    return 0;
}
EOF

    # 4. Compile the ELF binary
    gcc -o scanner.elf scanner.c

    # 5. Clean up setup files
    rm dummy.key dummy.crt scanner.c
    chmod 644 cert.enc
    chmod 755 scanner.elf

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
