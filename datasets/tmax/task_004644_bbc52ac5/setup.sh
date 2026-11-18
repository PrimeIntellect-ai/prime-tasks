#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssl
    pip3 install pytest cryptography

    mkdir -p /home/user
    cd /home/user

    # Generate a self-signed certificate for the embedded binary
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/key.pem -out /tmp/cert.pem -days 3650 -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=legacy-audit.local" -addext "subjectAltName=DNS:legacy-audit.local"

    # Format the PEM certificate as a C string
    CERT_CONTENT=$(cat /tmp/cert.pem | sed 's/^/\"/;s/$/\\n\"/')

    # Create the C source code
    cat <<EOF > /tmp/audit_agent.c
#include <stdio.h>

const char* embedded_cert = $CERT_CONTENT;
const char* target_ip = "TARGET_IP=203.0.113.85";

int main() {
    printf("Starting audit agent...\n");
    printf("Connecting to %s\n", target_ip);
    return 0;
}
EOF

    # Compile the binary
    gcc -O2 /tmp/audit_agent.c -o /home/user/audit_agent
    chmod 755 /home/user/audit_agent
    rm /tmp/audit_agent.c /tmp/cert.pem /tmp/key.pem

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
