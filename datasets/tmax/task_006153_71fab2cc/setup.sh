#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo openssl gawk
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Generate CA
    openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.pem -days 365 -nodes -subj "/CN=TrustedCA"

    # Generate a Valid Cert
    openssl req -newkey rsa:2048 -keyout valid.key -out valid.csr -nodes -subj "/CN=ValidClient"
    openssl x509 -req -in valid.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out valid.pem -days 365

    # Generate an Invalid Cert (Self-signed, not signed by CA)
    openssl req -x509 -newkey rsa:2048 -keyout invalid1.key -out invalid1.pem -days 365 -nodes -subj "/CN=RogueClient1"

    # Generate another Invalid Cert (Signed by a different CA)
    openssl req -x509 -newkey rsa:2048 -keyout fake_ca.key -out fake_ca.pem -days 365 -nodes -subj "/CN=FakeCA"
    openssl req -newkey rsa:2048 -keyout invalid2.key -out invalid2.csr -nodes -subj "/CN=RogueClient2"
    openssl x509 -req -in invalid2.csr -CA fake_ca.pem -CAkey fake_ca.key -CAcreateserial -out invalid2.pem -days 365

    # Format JSON logs
    VALID_PEM=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' valid.pem)
    INVALID1_PEM=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' invalid1.pem)
    INVALID2_PEM=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' invalid2.pem)

    cat <<EOF > logs.json
{"session_id": "SESS-1001", "client_ip": "192.168.1.10", "client_cert_pem": "${VALID_PEM}"}
{"session_id": "SESS-1002", "client_ip": "10.0.0.51", "client_cert_pem": "${INVALID1_PEM}"}
{"session_id": "SESS-1003", "client_ip": "172.16.0.4", "client_cert_pem": "${VALID_PEM}"}
{"session_id": "SESS-1004", "client_ip": "192.168.1.105", "client_cert_pem": "${INVALID2_PEM}"}
EOF

    # Encrypt the logs
    openssl enc -aes-256-cbc -pbkdf2 -in logs.json -out logs.enc -pass pass:audit_pass_2024

    # Cleanup intermediate files
    rm -f ca.key valid.* invalid* fake* logs.json ca.srl

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
