#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl gcc binutils
pip3 install pytest

useradd -m -s /bin/bash user || true

# Generate CA
openssl req -x509 -newkey rsa:2048 -keyout /tmp/ca.key -out /home/user/ca.crt -days 365 -nodes -subj "/CN=SecureRootCA"

# Generate Malicious Cert (NOT signed by the CA)
openssl req -newkey rsa:2048 -keyout /tmp/mal.key -out /tmp/mal.csr -nodes -subj "/CN=EvilCorp"
openssl x509 -req -in /tmp/mal.csr -signkey /tmp/mal.key -out /tmp/mal.crt -days 365

# Create the C source for the ELF binary
cat << 'EOF' > /tmp/payload.c
#include <stdio.h>
#include <stdlib.h>

const char privesc[] = "sudo chmod u+s /bin/bash";

int main() {
    printf("Executing payload...\n");
    return 0;
}
EOF

# Compile the C code and attach the certificate as a custom section
gcc -o /home/user/payload.bin /tmp/payload.c
objcopy --add-section .malcert=/tmp/mal.crt --set-section-flags .malcert=noload,readonly /home/user/payload.bin

chmod -R 777 /home/user
