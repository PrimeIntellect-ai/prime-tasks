#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    mkdir -p /home/user/certs

    # Generate CA
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/ca_key.pem -out /home/user/ca-chain.pem -days 365 -nodes -subj '/CN=My Root CA' 2>/dev/null

    # Generate rogue CA
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/rogue_ca_key.pem -out /home/user/rogue_ca.pem -days 365 -nodes -subj '/CN=Rogue CA' 2>/dev/null

    # Function to generate cert
    gen_cert() {
        local name=$1
        local ca_key=$2
        local ca_cert=$3
        openssl req -newkey rsa:2048 -keyout /home/user/certs/${name}_key.pem -out /home/user/certs/${name}.csr -nodes -subj "/CN=${name}" 2>/dev/null
        openssl x509 -req -in /home/user/certs/${name}.csr -CA ${ca_cert} -CAkey ${ca_key} -CAcreateserial -out /home/user/certs/${name}.pem -days 365 2>/dev/null
    }

    gen_cert client_1 /home/user/ca_key.pem /home/user/ca-chain.pem
    gen_cert client_2 /home/user/rogue_ca_key.pem /home/user/rogue_ca.pem
    gen_cert client_3 /home/user/ca_key.pem /home/user/ca-chain.pem
    gen_cert client_4 /home/user/ca_key.pem /home/user/ca-chain.pem
    gen_cert client_5 /home/user/ca_key.pem /home/user/ca-chain.pem

    # Create gateway_logs.json
    cat << 'EOF' > /home/user/gateway_logs.json
[
    {
        "req_id": 1,
        "client_cert_file": "client_1.pem",
        "payload": "{\"username\": \"admin\", \"password\": \"secure123\"}",
        "response_code": 200
    },
    {
        "req_id": 2,
        "client_cert_file": "client_2.pem",
        "payload": "{\"username\": \"admin' OR 1=1--\", \"password\": \"\"}",
        "response_code": 403
    },
    {
        "req_id": 3,
        "client_cert_file": "client_3.pem",
        "payload": "{\"username\": \"hacker<script>alert(1)</script>\", \"password\": \"test\"}",
        "response_code": 200
    },
    {
        "req_id": 4,
        "client_cert_file": "client_4.pem",
        "payload": "{\"username\": \"admin' OR '1'='1\", \"password\": \"pass\"}",
        "response_code": 200
    },
    {
        "req_id": 5,
        "client_cert_file": "client_5.pem",
        "payload": "{\"username\": \"admin' OR 1=1--\", \"password\": \"pass\"}",
        "response_code": 401
    }
]
EOF

    # Clean up CSRs and Keys
    rm -f /home/user/certs/*.csr /home/user/certs/*_key.pem /home/user/*_key.pem /home/user/*.srl /home/user/rogue_ca.pem

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
