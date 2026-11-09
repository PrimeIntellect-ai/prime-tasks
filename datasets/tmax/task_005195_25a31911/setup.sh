#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/certs
    mkdir -p /home/user/app/logs

    # Generate CA
    openssl req -new -x509 -days 365 -nodes -text -out /home/user/app/certs/ca.pem \
      -keyout /home/user/app/certs/ca.key -subj "/CN=Fake CA"

    # Generate Server Cert
    openssl req -new -nodes -text -out /home/user/app/certs/server.csr \
      -keyout /home/user/app/certs/server.key -subj "/CN=localhost"
    openssl x509 -req -in /home/user/app/certs/server.csr -text -days 365 \
      -CA /home/user/app/certs/ca.pem -CAkey /home/user/app/certs/ca.key -CAcreateserial \
      -out /home/user/app/certs/server.pem

    # Create access log
    cat << 'EOF' > /home/user/app/logs/access.log
192.168.1.1 - GET /index.html HTTP/1.1
192.168.1.50 - GET /api/data?key=AKIAIOSFODNN7EXAMPLE&query=UNION SELECT * FROM users HTTP/1.1
10.0.0.5 - POST /login HTTP/1.1
10.0.0.2 - GET /download?file=../../../../etc/passwd HTTP/1.1
192.168.1.100 - GET /status?token=AKIA1234567890ABCDEF HTTP/1.1
EOF

    touch /home/user/app/logs/secure.log
    touch /home/user/app/logs/debug.log

    chown -R user:user /home/user/app

    # Apply global permissions
    chmod -R 777 /home/user

    # Restore specific permissions required by the tests
    chmod 640 /home/user/app/logs/secure.log
    chmod 777 /home/user/app/logs/debug.log
    chmod 644 /home/user/app/logs/access.log
