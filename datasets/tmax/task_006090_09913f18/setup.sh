#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/login_handler.c
#include <stdio.h>
int main() {
    char *redirect = "https://malicious.example.com/redirect?url=http://trusted.com";
    printf("Login handler\n");
    return 0;
}
EOF
    gcc /tmp/login_handler.c -o /home/user/login_handler
    chmod 754 /home/user/login_handler

    mkdir -p /home/user/certs
    cd /home/user/certs

    openssl req -new -x509 -days 3650 -nodes -out ca.crt -keyout ca.key -subj "/CN=My Root CA"
    openssl req -new -nodes -out intermediate.csr -keyout intermediate.key -subj "/CN=My Intermediate CA"

    echo "basicConstraints=CA:TRUE" > extfile.cnf
    openssl x509 -req -in intermediate.csr -days 3650 -extfile extfile.cnf -CA ca.crt -CAkey ca.key -CAcreateserial -out intermediate.crt
    rm extfile.cnf

    openssl req -new -nodes -out server.csr -keyout server.key -subj "/CN=login.example.com"
    openssl x509 -req -in server.csr -days 3650 -CA intermediate.crt -CAkey intermediate.key -CAcreateserial -out server.crt

    chown -R user:user /home/user/certs /home/user/login_handler
    chmod -R 777 /home/user
