#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev xxd
    pip3 install pytest

    mkdir -p /home/user/certs

    # Generate CA
    openssl req -x509 -sha256 -nodes -days 3650 -newkey rsa:2048 -keyout /home/user/ca.key -out /home/user/ca.crt -subj "/CN=RootCA"

    # Generate Valid Client 1 (Benign Payload)
    openssl req -new -newkey rsa:2048 -nodes -keyout /home/user/certs/client1.key -out /home/user/certs/client1.csr -subj "/CN=Client1"
    openssl x509 -req -in /home/user/certs/client1.csr -CA /home/user/ca.crt -CAkey /home/user/ca.key -CAcreateserial -out /home/user/certs/client1.crt -days 365

    # Generate Invalid Client 2 (Fake CA, Benign Payload)
    openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout /home/user/certs/fake.key -out /home/user/certs/fake_ca.crt -subj "/CN=FakeCA"
    openssl req -new -newkey rsa:2048 -nodes -keyout /home/user/certs/client2.key -out /home/user/certs/client2.csr -subj "/CN=Client2"
    openssl x509 -req -in /home/user/certs/client2.csr -CA /home/user/certs/fake_ca.crt -CAkey /home/user/certs/fake.key -CAcreateserial -out /home/user/certs/client2.crt -days 365

    # Generate Valid Client 3 (Malicious Payload)
    openssl req -new -newkey rsa:2048 -nodes -keyout /home/user/certs/client3.key -out /home/user/certs/client3.csr -subj "/CN=Client3"
    openssl x509 -req -in /home/user/certs/client3.csr -CA /home/user/ca.crt -CAkey /home/user/ca.key -CAcreateserial -out /home/user/certs/client3.crt -days 365

    # Create Secret Key
    head -c 32 /dev/urandom > /home/user/secret.key

    # Helper to encrypt
    encrypt_payload() {
        local pt="$1"
        local iv=$(openssl rand -hex 16)
        local ct=$(echo -n "$pt" | openssl enc -aes-256-cbc -K $(xxd -p -c 32 /home/user/secret.key) -iv $iv | xxd -p -c 256 | tr -d '\n')
        echo "${iv}:${ct}"
    }

    # Create log file
    echo "client1.crt $(encrypt_payload "GET /index.html HTTP/1.1")" > /home/user/server.log
    echo "client2.crt $(encrypt_payload "GET /about.html HTTP/1.1")" >> /home/user/server.log
    echo "client3.crt $(encrypt_payload "POST /api HTTP/1.1 EXEC_SHELL command=whoami")" >> /home/user/server.log

    # Cleanup unnecessary keys
    rm -f /home/user/ca.key /home/user/certs/*.key /home/user/certs/*.csr /home/user/certs/fake_ca.crt /home/user/ca.srl

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
