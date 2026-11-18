#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang openssl coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/certs
    mkdir -p /home/user/payloads/input
    mkdir -p /home/user/payloads/output
    mkdir -p /home/user/rotator

    cd /home/user/certs

    # Generate Root CA
    openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout root.key -out root.crt -subj "/C=US/O=Security/CN=RootCA"

    # Generate Sub CA
    openssl req -newkey rsa:2048 -nodes -keyout sub.key -out sub.csr -subj "/C=US/O=Security/CN=SubCA"
    echo "basicConstraints=critical,CA:TRUE" > extfile.cnf
    openssl x509 -req -in sub.csr -CA root.crt -CAkey root.key -CAcreateserial -out sub.crt -days 365 -extfile extfile.cnf

    # Generate Leaf Cert
    openssl req -newkey rsa:2048 -nodes -keyout leaf.key -out leaf.csr -subj "/C=US/O=Security/CN=LeafCert"
    openssl x509 -req -in leaf.csr -CA sub.crt -CAkey sub.key -CAcreateserial -out leaf.crt -days 365

    cd /home/user/payloads/input

    # Create Payload 1
    INNER1='{"user":"Alice","ssn":"111-22-3333","old_token":"old.jwt.token1"}'
    B64_1=$(echo -n "$INNER1" | base64 -w 0)
    echo "{\"id\":\"payload_001\",\"data_b64\":\"$B64_1\"}" > payload_001.json

    # Create Payload 2
    INNER2='{"user":"Bob","ssn":"999-88-7777","old_token":"old.jwt.token2"}'
    B64_2=$(echo -n "$INNER2" | base64 -w 0)
    echo "{\"id\":\"payload_002\",\"data_b64\":\"$B64_2\"}" > payload_002.json

    chmod -R 777 /home/user
