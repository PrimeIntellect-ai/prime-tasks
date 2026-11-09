#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server openssl
    pip3 install pytest cryptography paramiko

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.ssh
    chmod 700 /home/user/.ssh

    # Generate payload SSH key
    ssh-keygen -t ed25519 -f /home/user/payload_key -N "" -q
    base64 /home/user/payload_key > /home/user/payload.b64
    rm /home/user/payload_key /home/user/payload_key.pub

    # Generate CA and Server Certs
    openssl req -x509 -newkey rsa:4096 -keyout /home/user/ca.key -out /home/user/ca.crt -days 365 -nodes -subj "/CN=RedTeam CA"
    openssl req -newkey rsa:2048 -keyout /home/user/server.key -out /home/user/server.csr -nodes -subj "/CN=127.0.0.1"
    openssl x509 -req -in /home/user/server.csr -CA /home/user/ca.crt -CAkey /home/user/ca.key -CAcreateserial -out /home/user/server.crt -days 365

    mkdir -p /run/sshd

    chown -R user:user /home/user/
    chmod -R 777 /home/user
