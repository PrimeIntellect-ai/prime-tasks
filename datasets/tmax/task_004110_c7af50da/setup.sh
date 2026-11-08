#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit
    cd /home/user/audit

    cat << 'EOF' > auth_helper.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        return 1;
    }
    char *secret = argv[1];
    printf("Processing with secret: %s\n", secret);
    return 0;
}
EOF

    # Generate CA
    openssl req -new -x509 -days 365 -nodes -text -out ca.crt \
      -keyout ca.key -subj "/CN=Test Root CA" 2>/dev/null

    # Generate Server Cert
    openssl req -new -nodes -text -out server.csr \
      -keyout server.key -subj "/CN=Test Server" 2>/dev/null
    openssl x509 -req -in server.csr -text -days 365 \
      -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt 2>/dev/null

    chmod -R 777 /home/user
