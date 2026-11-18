#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/api.php
<?php
$cmd = $_GET['cmd'];
system("ping -c 1 " . $cmd);
?>
EOF

    cat << 'EOF' > /home/user/app/auth.py
from flask import Flask, make_response, request

app = Flask(__name__)

@app.route('/login')
def login():
    resp = make_response("Logged in")
    resp.set_cookie('session_id', '1234567890abcdef')
    return resp
EOF

    cat << 'EOF' > /home/user/app/gen_cert.sh
#!/bin/bash
cd /home/user/app
openssl req -x509 -nodes -days 365 -newkey rsa:1024 -md5 -keyout server.key -out server.crt -subj "/CN=localhost" 2>/dev/null
EOF

    chmod +x /home/user/app/gen_cert.sh

    chmod -R 777 /home/user
