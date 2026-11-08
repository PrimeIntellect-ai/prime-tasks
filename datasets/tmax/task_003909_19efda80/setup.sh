#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libssl-dev binutils gdb xxd openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incident/certs
    cd /home/user/incident/certs

    # Generate CA
    openssl req -new -x509 -days 365 -nodes -keyout ca.key -out ca.crt -subj "/CN=Malicious Root CA"

    # Generate Intermediate
    openssl req -new -newkey rsa:2048 -nodes -keyout intermediate.key -out intermediate.csr -subj "/CN=Malicious Intermediate"
    echo "basicConstraints=CA:TRUE" > extfile.cnf
    openssl x509 -req -in intermediate.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out intermediate.crt -days 365 -extfile extfile.cnf
    rm extfile.cnf

    # Generate Leaf
    openssl req -new -newkey rsa:2048 -nodes -keyout leaf.key -out leaf.csr -subj "/CN=Malicious Leaf C2"
    openssl x509 -req -in leaf.csr -CA intermediate.crt -CAkey intermediate.key -CAcreateserial -out leaf.crt -days 365

    cd /home/user/incident

    # Create beacon.elf C source
    cat << 'EOF' > beacon_src.c
#include <stdio.h>
#include <string.h>

void init_crypto() {
    // The key the agent needs to find
    volatile char key[17] = "M4lw4r3K3y123456";
    printf("Crypto initialized.\n");
}

int main() {
    init_crypto();
    return 0;
}
EOF
    gcc -O0 -o beacon.elf beacon_src.c
    rm beacon_src.c

    # Create and encrypt the payload
    echo -n "C2_SERVER=198.51.100.42" > raw_payload.txt
    # Hex key for "M4lw4r3K3y123456" is 4d346c773472334b3379313233343536
    openssl enc -aes-128-cbc -in raw_payload.txt -out payload.enc -K 4d346c773472334b3379313233343536 -iv 0102030405060708090a0b0c0d0e0f10
    rm raw_payload.txt

    chown -R user:user /home/user/incident
    chmod -R 777 /home/user
