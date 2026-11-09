#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl gcc binutils faketime

    pip3 install pytest

    mkdir -p /home/user/incident

    # Generate Certificate Chain
    # 1. Root CA (Valid)
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /tmp/root.key -out /tmp/root.crt -subj "/C=US/ST=CA/O=Corp/CN=RootCA" 2>/dev/null

    # 2. Intermediate (Expired)
    openssl req -new -nodes -newkey rsa:2048 -keyout /tmp/inter.key -out /tmp/inter.csr -subj "/C=US/ST=CA/O=Corp/CN=evil.bastion.local" 2>/dev/null
    # Use faketime to generate a certificate in the past so it's expired today
    faketime '2020-01-01 00:00:00' openssl x509 -req -in /tmp/inter.csr -CA /tmp/root.crt -CAkey /tmp/root.key -CAcreateserial -out /tmp/inter.crt -days 365 2>/dev/null

    # 3. Leaf (Valid but signed by expired)
    openssl req -new -nodes -newkey rsa:2048 -keyout /tmp/leaf.key -out /tmp/leaf.csr -subj "/C=US/ST=CA/O=Corp/CN=app.internal" 2>/dev/null
    openssl x509 -req -in /tmp/leaf.csr -CA /tmp/inter.crt -CAkey /tmp/inter.key -CAcreateserial -out /tmp/leaf.crt -days 3650 2>/dev/null

    # Combine them into chain.pem
    cat /tmp/root.crt /tmp/inter.crt /tmp/leaf.crt > /home/user/incident/chain.pem
    rm /tmp/root.* /tmp/inter.* /tmp/leaf.*

    # Generate malicious ELF binary
    echo "int main(){return 0;}" > /tmp/dummy.c
    gcc /tmp/dummy.c -o /home/user/incident/auth_helper
    # Payload: {"user":"backdoor","role":"system"} -> base64: eyJ1c2VyIjoiYmFja2Rvb3IiLCJyb2xlIjoic3lzdGVtIn0
    echo -n "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiYmFja2Rvb3IiLCJyb2xlIjoic3lzdGVtIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" > /tmp/token.bin
    objcopy --add-section .backdoor=/tmp/token.bin /home/user/incident/auth_helper
    rm /tmp/dummy.c /tmp/token.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
