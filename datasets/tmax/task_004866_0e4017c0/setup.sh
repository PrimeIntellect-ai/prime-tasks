#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl iptables
    pip3 install pytest

    mkdir -p /home/user/certs

    # Generate CA
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/certs/ca.key -out /home/user/certs/ca.pem -days 365 -nodes -subj "/CN=MyRootCA"

    # Generate alpha.local (valid)
    openssl req -newkey rsa:2048 -keyout /home/user/certs/alpha.key -out /home/user/certs/alpha.csr -nodes -subj "/CN=alpha.local"
    openssl x509 -req -in /home/user/certs/alpha.csr -CA /home/user/certs/ca.pem -CAkey /home/user/certs/ca.key -CAcreateserial -out /home/user/certs/alpha.local.pem -days 365

    # Generate beta.local (invalid, self-signed)
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/certs/beta.key -out /home/user/certs/beta.local.pem -days 365 -nodes -subj "/CN=beta.local"

    # Generate gamma.local (valid)
    openssl req -newkey rsa:2048 -keyout /home/user/certs/gamma.key -out /home/user/certs/gamma.csr -nodes -subj "/CN=gamma.local"
    openssl x509 -req -in /home/user/certs/gamma.csr -CA /home/user/certs/ca.pem -CAkey /home/user/certs/ca.key -CAcreateserial -out /home/user/certs/gamma.local.pem -days 365

    # Create traffic.log
    cat << 'EOF' > /home/user/traffic.log
[2023-10-01T10:00:00Z] 192.168.1.50 alpha.local GET /index.html HTTP/1.1
[2023-10-01T10:05:00Z] 10.0.0.12 beta.local GET /about.html HTTP/1.1
[2023-10-01T10:10:00Z] 172.16.5.99 alpha.local GET /images/logo.png HTTP/1.1
[2023-10-01T10:15:00Z] 192.168.1.105 gamma.local GET /api/data?query=1+UNION+SELECT+* HTTP/1.1
[2023-10-01T10:20:00Z] 10.0.0.12 beta.local GET /contact HTTP/1.1
[2023-10-01T10:25:00Z] 172.16.5.100 gamma.local GET /assets/../../etc/passwd HTTP/1.1
[2023-10-01T10:30:00Z] 192.168.1.50 gamma.local GET /search?q=%3Cscript%3Ealert(1)%3C/script%3E HTTP/1.1
[2023-10-01T10:35:00Z] 8.8.8.8 alpha.local GET /favicon.ico HTTP/1.1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
