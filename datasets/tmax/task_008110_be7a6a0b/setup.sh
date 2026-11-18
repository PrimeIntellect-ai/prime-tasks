#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssl faketime curl
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/certs

    # 1. Create redirect.log with XOR key 0x42
    cat << 'EOF' > /home/user/logs/redirect.log
[INFO] Redirecting to /admin, sig: 2d232f2b2c
[INFO] Redirecting to /home, sig: 2a2d2f27
[INFO] Redirecting to /profile, sig: 32302d242b2e27
EOF

    # 2. Generate certificates
    cd /home/user/certs

    # CA
    openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.crt -days 365 -nodes -subj "/CN=RedTeam CA"

    # Valid cert (client2)
    openssl req -newkey rsa:2048 -keyout client2.key -out client2.csr -nodes -subj "/CN=Valid Client"
    openssl x509 -req -in client2.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out client2.crt -days 30

    # Expired cert (client1) - using faketime to create an already expired certificate
    openssl req -newkey rsa:2048 -keyout client1.key -out client1.csr -nodes -subj "/CN=Expired Client"
    faketime '2020-01-01 00:00:00' openssl x509 -req -in client1.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out client1.crt -days 30

    # Invalid signature cert (client3 - signed by different CA)
    openssl req -x509 -newkey rsa:2048 -keyout rogue.key -out rogue.crt -days 365 -nodes -subj "/CN=Rogue CA"
    openssl req -newkey rsa:2048 -keyout client3.key -out client3.csr -nodes -subj "/CN=Rogue Client"
    openssl x509 -req -in client3.csr -CA rogue.crt -CAkey rogue.key -CAcreateserial -out client3.crt -days 30

    # Create the user
    useradd -m -s /bin/bash user || true

    # End with making home writable, then specifically set the insecure permissions required by the test
    chmod -R 777 /home/user
    chmod 644 /home/user/certs/*.key
    chmod 644 /home/user/certs/*.crt
    chown -R user:user /home/user/logs /home/user/certs
