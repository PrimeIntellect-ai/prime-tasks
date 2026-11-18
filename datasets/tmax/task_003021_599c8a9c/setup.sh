#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl gcc binutils faketime
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/certs
    cd /home/user/certs

    # Generate CA
    openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -keyout ca.key -out ca.crt -subj "/CN=LegacyCA"

    # Generate Client 1 (Signed by CA, but EXPIRED)
    openssl req -newkey rsa:2048 -nodes -keyout client1.key -out client1.csr -subj "/CN=Client1"
    faketime '2010-01-01' openssl x509 -req -in client1.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out client1.crt -days 10

    # Generate Fake CA for Client 2
    openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -keyout fake_ca.key -out fake_ca.crt -subj "/CN=FakeCA"

    # Generate Client 2 (Valid date, but signed by Fake CA)
    openssl req -newkey rsa:2048 -nodes -keyout client2.key -out client2.csr -subj "/CN=Client2"
    openssl x509 -req -in client2.csr -CA fake_ca.crt -CAkey fake_ca.key -CAcreateserial -out client2.crt -days 3650

    # Generate Client 3 (Valid date, signed by actual CA)
    openssl req -newkey rsa:2048 -nodes -keyout client3.key -out client3.csr -subj "/CN=Client3"
    openssl x509 -req -in client3.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out client3.crt -days 3650

    cd /home/user

    # Create the legacy_auth binary with a hardcoded token
    cat << 'EOF' > legacy_auth.c
#include <stdio.h>
#include <string.h>

const char* fallback_token = "F4llb4ck_Adm1n_992#";

int main(int argc, char** argv) {
    if(argc > 1 && strcmp(argv[1], fallback_token) == 0) {
        printf("Access Granted.\n");
    } else {
        printf("Access Denied.\n");
    }
    return 0;
}
EOF

    gcc legacy_auth.c -o legacy_auth
    rm legacy_auth.c

    chown -R user:user /home/user/certs /home/user/legacy_auth
    chmod -R 777 /home/user
