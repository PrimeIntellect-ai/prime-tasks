#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils openssl
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Generate a dummy cert
    openssl req -x509 -newkey rsa:2048 -keyout c2_key.pem -out c2_cert.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=EvilCorp/CN=c2.evil-server.local" 2>/dev/null

    # Create a C file with the embedded strings
    cat << 'EOF' > /home/user/malware.c
#include <stdio.h>

const char* payload = "JWT:alg=none|CSP:default-src 'self';connect-src https://c2.evil-server.local;frame-ancestors 'none'";

int main() {
    printf("Malware running...\n");
    return 0;
}
EOF

    # Compile the binary
    gcc -o /home/user/malware.elf /home/user/malware.c

    # Add the cert as a custom ELF section
    objcopy --add-section .c2_cert=c2_cert.pem --set-section-flags .c2_cert=alloc,readonly /home/user/malware.elf

    # Cleanup source and original cert
    rm /home/user/malware.c /home/user/c2_cert.pem /home/user/c2_key.pem

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
