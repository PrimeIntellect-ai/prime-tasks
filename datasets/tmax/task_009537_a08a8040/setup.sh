#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++
    pip3 install pytest

    mkdir -p /home/user/evidence
    mkdir -p /home/user/.ssh

    cat << 'EOF' > /home/user/evidence/stealer.c
#include <stdio.h>
int main() {
    const char* ip = "EXFIL_IP:198.51.100.77";
    const char* key = "XOR_KEY:0x3F";
    printf("Stealer running...\n");
    return 0;
}
EOF
    gcc /home/user/evidence/stealer.c -o /home/user/evidence/stealer.bin
    rm /home/user/evidence/stealer.c

    python3 -c '
plaintext = b"root_db_pass:Sup3rS3cr3t!99"
key = 0x3F
ciphertext = bytes([b ^ key for b in plaintext])
with open("/home/user/evidence/payload.enc", "wb") as f:
    f.write(ciphertext)
'

    cat << 'EOF' > /home/user/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3... user@legitimate-machine
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... attacker@exfil-server
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDf... admin@jumpbox
EOF
    chmod 644 /home/user/.ssh/authorized_keys

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
