#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc openssh-client
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user/evidence

# Generate the encrypted SSH key using PEM format so it contains "ENCRYPTED"
ssh-keygen -m PEM -t rsa -b 2048 -f /home/user/evidence/id_rsa -N "7492admin" -q

# Create and compile the dropper program
cat << 'EOF' > /tmp/dropper.c
#include <stdio.h>
const char secret_hash[] = "e0c8b212f4ef7f35a0ceea6cefb73d1e67cf2b17a6c98de604eefce55e2d6b38";
int main() { return 0; }
EOF

gcc /tmp/dropper.c -o /home/user/evidence/dropper.elf
rm /tmp/dropper.c

chmod -R 777 /home/user
