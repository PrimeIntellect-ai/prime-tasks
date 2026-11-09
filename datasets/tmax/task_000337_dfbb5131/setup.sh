#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    mkdir -p /home/user/traffic_data
    cd /home/user/traffic_data

    # Create real root CA
    openssl req -x509 -newkey rsa:2048 -keyout rootCA.key -out rootCA.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=RootCA"

    # Create fake root CA for the forged cert
    openssl req -x509 -newkey rsa:2048 -keyout fakeCA.key -out fakeCA.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=HackerOrg/CN=FakeCA"

    # Create a client cert signed by the fake CA (will fail validation against rootCA.crt)
    openssl req -newkey rsa:2048 -keyout client.key -out client.csr -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=Client"
    openssl x509 -req -in client.csr -CA fakeCA.crt -CAkey fakeCA.key -CAcreateserial -out client.crt -days 365

    # Create the payload.txt
    echo -n '{"source_ip": "198.51.100.123", "cert": "client.crt"}' | base64 > payload.txt

    # Clean up keys to prevent agent from cheating by analyzing keys
    rm -f rootCA.key fakeCA.key fakeCA.crt client.key client.csr fakeCA.srl

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/traffic_data
    chmod -R 777 /home/user
