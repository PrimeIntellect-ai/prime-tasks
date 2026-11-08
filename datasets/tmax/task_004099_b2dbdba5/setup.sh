#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create auth.log
    cat << 'EOF' > /home/user/auth.log
2023-10-01 10:00:01 [INFO] User admin logged in. Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFkbWluIiwicm9sZSI6ImFkbWluIn0.signature1
2023-10-01 10:05:23 [INFO] User guest_user logged in. Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6Imd1ZXN0X3VzZXIiLCJyb2xlIjoiZ3Vlc3QifQ.signature2
EOF

    # Generate server.crt
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/key.pem -out /home/user/server.crt -days 3650 -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=auth.internal.corp" -addext "subjectAltName=DNS:auth.internal.corp,DNS:backup.internal.corp" -set_serial 1

    # Create legacy_auth.py and compile to pyc
    cat << 'EOF' > /home/user/legacy_auth.py
def check_auth():
    API_KEY = "xK9#mP2$vL"
    return True
EOF
    python3 -m py_compile /home/user/legacy_auth.py
    mv /home/user/__pycache__/legacy_auth.cpython-*.pyc /home/user/legacy_auth.pyc
    rm -rf /home/user/legacy_auth.py /home/user/__pycache__

    chmod -R 777 /home/user
