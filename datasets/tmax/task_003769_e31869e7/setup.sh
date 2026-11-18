#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/webapp/certs /home/user/webapp/web_root /home/user/webapp/logs /home/user/audit

    # 1. Create Certs
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/webapp/certs/server.key -out /home/user/webapp/certs/server.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/CN=example.com"

    # 2. Create web_root and checksums
    echo "<html><body>Hello</body></html>" > /home/user/webapp/web_root/index.html
    echo "body { color: red; }" > /home/user/webapp/web_root/style.css
    echo "console.log('original');" > /home/user/webapp/web_root/app.js

    cd /home/user/webapp/web_root
    sha256sum index.html style.css app.js > /home/user/webapp/checksums.txt

    # Tamper with a file
    echo "console.log('tampered!!');" > /home/user/webapp/web_root/app.js

    # 3. Create access.log
    cat << 'EOF' > /home/user/webapp/logs/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /api/auth?password=supersecret&username=john HTTP/1.1" 200 123
10.0.0.5 - - [10/Oct/2023:13:55:40 -0700] "GET /hidden_page HTTP/1.1" 404 232
10.0.0.5 - - [10/Oct/2023:13:55:41 -0700] "GET /admin_backup.zip HTTP/1.1" 404 232
10.0.0.5 - - [10/Oct/2023:13:55:42 -0700] "GET /config.php.bak HTTP/1.1" 404 232
192.168.1.20 - - [10/Oct/2023:13:56:01 -0700] "GET /profile?ssn=123-456-7890&token=abcdef123 HTTP/1.1" 200 500
172.16.0.2 - - [10/Oct/2023:13:57:00 -0700] "GET /nonexistent HTTP/1.1" 404 111
172.16.0.2 - - [10/Oct/2023:13:57:05 -0700] "GET /fake_path HTTP/1.1" 404 111
192.168.1.50 - - [10/Oct/2023:13:58:00 -0700] "GET /missing HTTP/1.1" 404 111
EOF

    chown -R user:user /home/user/webapp /home/user/audit
    chmod -R 777 /home/user
