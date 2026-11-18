#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl curl
    pip3 install pytest

    # Setup required before the agent starts
    mkdir -p /home/user/certs
    echo "PORT      STATE SERVICE\n22/tcp    open  ssh\n80/tcp    open  http\n443/tcp   open  https\n9001/tcp  open  supervisord\n31337/tcp open  internal-admin-api\n" > /home/user/scan_results.txt

    # Create dummy vault file
    echo "SECRET_FLAG_{evasion_master_992}" > /home/user/vault.data

    # Generate Certificates
    cd /home/user/certs
    openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=RedTeam/OU=Root/CN=RedTeamRootCA"
    openssl req -newkey rsa:2048 -keyout server.key -out server.csr -nodes -subj "/C=US/ST=State/L=City/O=RedTeam/OU=Target/CN=V3ryS3cr3tM4cK3y!2024"
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365
    rm ca.key server.key server.csr

    chmod -R 755 /home/user/certs
    chmod 644 /home/user/scan_results.txt /home/user/vault.data

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
