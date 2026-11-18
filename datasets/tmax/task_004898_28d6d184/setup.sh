#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/server_data/www

    # Create original files
    echo "<html><body>Welcome</body></html>" > /home/user/server_data/www/index.html
    echo "function init() { console.log('Ready'); }" > /home/user/server_data/www/app.js
    echo "body { color: black; }" > /home/user/server_data/www/style.css
    echo "<?php phpinfo(); ?>" > /home/user/server_data/www/info.php

    # Generate hashes.txt from original files
    cd /home/user/server_data/www
    sha256sum * > /home/user/server_data/hashes.txt

    # Modify app.js to simulate compromise
    echo "function init() { console.log('Ready'); eval(atob('YmFkIGNvZGU=')); }" > /home/user/server_data/www/app.js

    # Generate the rogue certificate
    cd /home/user/server_data
    openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes -subj "/C=US/ST=CA/L=SF/O=Evil Corp/CN=EvilRogueCA-999"

    # Create access logs
    cat << 'EOF' > /home/user/server_data/access.log
192.168.1.50 - - [10/Oct/2023:13:55:36 +0000] "GET /index.html HTTP/1.1" 200 1024 "-" "Mozilla/5.0"
10.0.0.12 - - [10/Oct/2023:13:56:01 +0000] "GET /style.css HTTP/1.1" 200 512 "-" "Mozilla/5.0"
203.0.113.8 - - [10/Oct/2023:14:01:22 +0000] "GET /app.js?cmd=base64_decode(MTIz) HTTP/1.1" 200 2048 "-" "Curl/7.68.0"
192.168.1.50 - - [10/Oct/2023:14:05:10 +0000] "GET /info.php HTTP/1.1" 200 4096 "-" "Mozilla/5.0"
EOF

    chown -R user:user /home/user/server_data
    chmod -R 777 /home/user
