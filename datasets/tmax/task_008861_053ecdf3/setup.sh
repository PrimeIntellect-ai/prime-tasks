#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils openssl iptables
    pip3 install pytest

    mkdir -p /home/user/evidence/

    cat << 'EOF' > /tmp/beacon.c
#include <stdio.h>
int main() {
    const char* ip = "C2_HOST=203.0.113.85";
    const char* port = "C2_PORT=4444";
    printf("Beaconing...\n");
    return 0;
}
EOF
    gcc /tmp/beacon.c -o /home/user/evidence/beacon
    rm /tmp/beacon.c

    echo "MISSION_ACCOMPLISHED_EVIDENCE_SECURED" > /tmp/plain.txt
    openssl enc -aes-256-cbc -pbkdf2 -salt -in /tmp/plain.txt -out /home/user/evidence/stolen_data.enc -pass pass:7391
    rm /tmp/plain.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
