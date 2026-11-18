#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gcc openssl binutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # 1. Create Root CA and Certificates
    openssl genrsa -out root_ca.key 2048
    openssl req -x509 -new -nodes -key root_ca.key -sha256 -days 1024 -out root_ca.pem -subj "/C=US/ST=State/L=City/O=Company/CN=RootCA"

    openssl genrsa -out app.key 2048
    openssl req -new -key app.key -out app.csr -subj "/C=US/ST=State/L=City/O=Company/CN=AppCert"
    openssl x509 -req -in app.csr -CA root_ca.pem -CAkey root_ca.key -CAcreateserial -out app.pem -days 500 -sha256

    # Create cert chain file
    cat app.pem > cert_chain.pem

    # 2. Create the target_app ELF binary
    cat << 'EOF' > dummy_app.c
#include <stdio.h>
int main() {
    printf("Running target app...\n");
    return 0;
}
EOF
    gcc dummy_app.c -o target_app

    # 3. Create a valid CSP policy file
    echo -n "default-src 'self'; script-src 'self' https://trusted.cdn.com; object-src 'none';" > csp_policy.txt

    # 4. Embed sections into the ELF
    objcopy --add-section .csp_policy=csp_policy.txt --set-section-flags .csp_policy=readonly \
            --add-section .cert_chain=cert_chain.pem --set-section-flags .cert_chain=readonly \
            target_app

    # Cleanup intermediate files except what is needed by the user
    rm -f dummy_app.c root_ca.key app.key app.csr app.pem cert_chain.pem csp_policy.txt root_ca.srl

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
