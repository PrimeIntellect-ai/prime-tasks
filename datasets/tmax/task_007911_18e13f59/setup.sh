#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-client openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/investigation/ssh_keys
    ssh-keygen -t rsa -b 2048 -f /home/user/investigation/ssh_keys/id_rsa_A -N "" -m PEM
    ssh-keygen -t rsa -b 2048 -f /home/user/investigation/ssh_keys/id_rsa_B -N "" -m PEM
    ssh-keygen -t rsa -b 2048 -f /home/user/investigation/ssh_keys/id_rsa_C -N "" -m PEM

    cd /home/user/investigation

    # 1. Root CA
    openssl req -x509 -new -nodes -keyout ca.key -sha256 -days 1024 -out ca.crt -subj "/C=US/ST=State/L=City/O=RootCA/CN=RootCA"

    # 2. Intermediate CA
    openssl req -new -nodes -keyout intermediate.key -out intermediate.csr -subj "/C=US/ST=State/L=City/O=InterCA/CN=InterCA"
    printf "basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n" > extfile.cnf
    openssl x509 -req -in intermediate.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out intermediate.crt -days 500 -sha256 -extfile extfile.cnf

    # 3. Server Cert (Reusing id_rsa_B)
    openssl req -new -key ssh_keys/id_rsa_B -out server.csr -subj "/C=US/ST=State/L=City/O=Device/CN=embedded.local"
    openssl x509 -req -in server.csr -CA intermediate.crt -CAkey intermediate.key -CAcreateserial -out server.crt -days 365 -sha256

    # Cleanup unnecessary setup files
    rm -f ca.key intermediate.key intermediate.csr server.csr ca.srl intermediate.srl extfile.cnf

    # Fix permissions
    chown -R user:user /home/user/investigation
    chmod 600 /home/user/investigation/ssh_keys/*
    chmod 755 /home/user/investigation/ssh_keys

    chmod -R 777 /home/user
