#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssl binutils gawk
    pip3 install pytest

    mkdir -p /home/user

    # Create the dummy server binary
    cat << 'EOF' > /home/user/server_source.c
#include <stdio.h>
int main() {
    printf("Starting legacy web server...\n");
    return 0;
}
EOF
    gcc /home/user/server_source.c -o /home/user/server_bin
    rm /home/user/server_source.c

    # Create the TLS certificate
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/server.key -out /home/user/server.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Legacy Corp/CN=legacy.local" 2>/dev/null

    # Calculate ground truth
    ENTRY_POINT=$(readelf -h /home/user/server_bin | grep 'Entry point address:' | awk '{print $4}')
    CERT_EXPIRY=$(openssl x509 -in /home/user/server.crt -noout -enddate | cut -d= -f2)

    # Save ground truth for test verifier (not visible to agent)
    echo "Entry: ${ENTRY_POINT}" > /tmp/expected_audit_line1.txt
    echo "Expiry: ${CERT_EXPIRY}" > /tmp/expected_audit_line2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
