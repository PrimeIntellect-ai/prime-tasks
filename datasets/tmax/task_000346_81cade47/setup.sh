#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl coreutils
    pip3 install pytest

    mkdir -p /home/user/pentest
    cd /home/user/pentest

    # 1. Create the binary file
    echo "malicious_payload_data_v1.0.42" > server.bin

    # 2. Create the auth_capture.txt
    JSON_PAYLOAD='{"client_id": "admin-override-99", "file_hash": "e65f3fcd4849eece2a5d2eb3d4bd818e983bc2c12d4a13a85b9b65dc9b3846db"}'
    B64_PAYLOAD=$(echo -n "$JSON_PAYLOAD" | base64 -w 0)

    cat <<EOF > auth_capture.txt
GET /api/v1/secure/download HTTP/1.1
Host: vulnerable.local
Authorization: Bearer $B64_PAYLOAD
Accept: */*
EOF

    # 3. Create a self-signed TLS certificate
    openssl genrsa -out rootCA.key 2048
    openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 1024 -out rootCA.crt -subj "/C=US/ST=State/O=Security/CN=Global Trust Root CA"

    openssl genrsa -out server.key 2048
    openssl req -new -key server.key -out server.csr -subj "/C=US/ST=State/O=Server/CN=vulnerable.local"
    openssl x509 -req -in server.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out server.crt -days 500 -sha256

    rm -f server.key rootCA.key rootCA.crt rootCA.srl server.csr

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/pentest
    chmod -R 777 /home/user
