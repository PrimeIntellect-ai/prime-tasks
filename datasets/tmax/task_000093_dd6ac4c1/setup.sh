#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/web_root /home/user/logs /home/user/certs
    mkdir -p /home/user/web_root/images

    cat << 'EOF' > /home/user/web_root/index.html
<!DOCTYPE html>
<html>
<head>
<title>Staging</title>
</head>
<body>
<h1>Welcome</h1>
</body>
</html>
EOF

    touch /home/user/web_root/app.js
    touch /home/user/web_root/style.css
    touch /home/user/web_root/images/logo.png

    cat << 'EOF' > /home/user/logs/app.log
[INFO] User login successful
[DEBUG] Processing payment for CC: 4111-2222-3333-4444
[INFO] User updated profile
[DEBUG] Failed payment for CC: 5555-6666-7777-8888, retrying...
[INFO] Logout
EOF

    chmod -R 777 /home/user
