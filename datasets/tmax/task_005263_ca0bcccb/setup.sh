#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl openssh-client bsdmainutils
    pip3 install pytest cryptography

    mkdir -p /home/user/.ssh
    chmod 700 /home/user/.ssh

    cd /home/user
    openssl genrsa -out ca.key 2048
    openssl req -x509 -new -nodes -key ca.key -sha256 -days 1024 -out ca.crt -subj "/C=US/ST=State/L=City/O=Company/CN=RootCA"
    openssl genrsa -out server.key 2048
    openssl req -new -key server.key -out server.csr -subj "/C=US/ST=State/L=City/O=Company/CN=server.local"
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 500 -sha256

    ssh-keygen -t rsa -b 2048 -f /home/user/temp_id_rsa -N "" -q
    base64 /home/user/temp_id_rsa > /home/user/ssh_key_b64.txt

    openssl rand -out /home/user/sym.key 32
    ssh-keygen -f /home/user/temp_id_rsa -e -m PEM > /home/user/temp_pub.pem
    openssl pkeyutl -encrypt -pubin -inkey /home/user/temp_pub.pem -in /home/user/sym.key -out /home/user/sym.key.enc

    openssl rand -out /home/user/iv.bin 16
    echo -n "CRITICAL_PAYLOAD_DATA_XYZ_12345" > /home/user/plaintext.txt

    HEX_KEY=$(hexdump -v -e '/1 "%02X"' /home/user/sym.key)
    HEX_IV=$(hexdump -v -e '/1 "%02X"' /home/user/iv.bin)
    openssl enc -aes-256-cbc -in /home/user/plaintext.txt -out /home/user/traffic.enc -K $HEX_KEY -iv $HEX_IV

    rm -f /home/user/temp_id_rsa /home/user/temp_id_rsa.pub /home/user/temp_pub.pem /home/user/plaintext.txt /home/user/server.csr /home/user/server.key /home/user/ca.key /home/user/ca.srl /home/user/sym.key

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
