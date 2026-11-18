#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/service/bin
    mkdir -p /home/user/service/public
    mkdir -p /home/user/service/cert
    mkdir -p /home/user/service/logs

    touch /home/user/service/bin/helper
    touch /home/user/service/bin/run

    echo "<html>Welcome</html>" > /home/user/service/public/index.html
    echo "var config = { admin: false };" > /home/user/service/public/config.js

    sha256sum /home/user/service/public/index.html > /home/user/service/hashes.txt
    sha256sum /home/user/service/public/config.js >> /home/user/service/hashes.txt

    echo "var config = { admin: true }; // pwned" > /home/user/service/public/config.js

    cat << 'EOF' > /home/user/service/logs/response.bin
HTTP/1.1 200 OK
Date: Mon, 01 Jan 2024 12:00:00 GMT
Server: Apache
Set-Cookie: session_id=abc; Path=/
Set-Cookie: admin_session=supersecrettoken99; Path=/; HttpOnly
Content-Type: text/html

<html><body>Dashboard</body></html>
EOF

    openssl req -x509 -nodes -days 1 -newkey rsa:2048 -keyout /home/user/service/cert/server.key -out /home/user/service/cert/server.crt -subj "/CN=old.localhost" 2>/dev/null

    chmod -R 777 /home/user

    # Set correct permissions after the global chmod
    chmod 4755 /home/user/service/bin/helper
    chmod 755 /home/user/service/bin/run
