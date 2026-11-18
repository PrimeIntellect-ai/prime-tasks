#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ espeak-ng coreutils
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak-ng -w /app/intercept.wav "The authorized key ends with uppercase X Y Z seven N Q equals equals."

    # Generate traffic.log
    echo -n "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCasbcd1234...XYZ7NQ== admin@10.0.0.1" | base64 -w 0 > /tmp/p1.b64
    echo "" >> /tmp/p1.b64
    echo -n "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCadmin4567...QWE32== user@localhost" | base64 -w 0 > /tmp/p2.b64
    echo "" >> /tmp/p2.b64

    echo "PAYLOAD:$(cat /tmp/p1.b64)" > /app/traffic.log
    echo "PAYLOAD:$(cat /tmp/p2.b64)" >> /app/traffic.log

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/process_keys.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>

int main() {
    // TODO: Read /app/traffic.log
    // TODO: Decode base64 payloads
    // TODO: Find the key matching the audio intercept suffix
    // TODO: Redact sensitive IP addresses
    // TODO: Output the correct key
    return 0;
}
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
