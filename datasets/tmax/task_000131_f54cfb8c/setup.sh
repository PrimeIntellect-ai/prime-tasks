#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl jq coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/tokens /home/user/logs /home/user/certs /home/user/keys

    # 1. JWT Setup
    header1=$(echo -n '{"alg":"HS256","typ":"JWT"}' | base64 | tr '+/' '-_' | tr -d '=')
    payload1=$(echo -n '{"user":"admin"}' | base64 | tr '+/' '-_' | tr -d '=')
    echo "$header1.$payload1.signature123" > /home/user/tokens/token_a.jwt

    header2=$(echo -n '{"alg":"none","typ":"JWT"}' | base64 | tr '+/' '-_' | tr -d '=')
    payload2=$(echo -n '{"user":"hacker"}' | base64 | tr '+/' '-_' | tr -d '=')
    echo "$header2.$payload2." > /home/user/tokens/token_b.jwt

    header3=$(echo -n '{"alg": "none" , "typ": "JWT"}' | base64 | tr '+/' '-_' | tr -d '=')
    payload3=$(echo -n '{"user":"guest"}' | base64 | tr '+/' '-_' | tr -d '=')
    echo "$header3.$payload3." > /home/user/tokens/token_c.jwt

    # 2. Log Setup
    cat << 'EOF' > /home/user/logs/access.log
127.0.0.1 - GET /index.html 200
127.0.0.1 - GET /api/data?q=1 200
192.168.1.5 - GET /search?q=<script>alert(1)</script> 400
10.0.0.2 - POST /login 200
10.0.0.2 - GET /users?id=1 UNION SELECT username,password FROM users 200
127.0.0.1 - GET /health 200
EOF

    # 3. Cert Setup
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/certs/ca.key -out /home/user/certs/ca.pem -days 365 -nodes -subj "/CN=MyRootCA" >/dev/null 2>&1
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/certs/other_ca.key -out /home/user/certs/other_ca.pem -days 365 -nodes -subj "/CN=OtherRootCA" >/dev/null 2>&1
    openssl req -newkey rsa:2048 -keyout /home/user/certs/server.key -out /home/user/certs/server.csr -nodes -subj "/CN=localhost" >/dev/null 2>&1
    openssl x509 -req -in /home/user/certs/server.csr -CA /home/user/certs/other_ca.pem -CAkey /home/user/certs/other_ca.key -CAcreateserial -out /home/user/certs/server.pem -days 365 >/dev/null 2>&1

    # 4. Keys Setup
    echo "secret1" > /home/user/keys/app_key.pem
    echo "secret2" > /home/user/keys/backup_key.pem
    echo "secret3" > /home/user/keys/test_key.pem

    chown -R user:user /home/user
    chmod -R 777 /home/user

    # Fix permissions specifically for the keys to test the agent
    chmod 600 /home/user/keys/app_key.pem
    chmod 644 /home/user/keys/backup_key.pem
    chmod 700 /home/user/keys/test_key.pem
