#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app_package

    # Create the python source and compile it
    cat << 'EOF' > /home/user/app_package/legacy_auth.py
import base64
def generate_token(user_id):
    key = 42
    encrypted = bytearray()
    for char in user_id:
        encrypted.append(ord(char) ^ key)
    return base64.b64encode(encrypted).decode('utf-8')
EOF

    python3 -c "import py_compile; py_compile.compile('/home/user/app_package/legacy_auth.py', cfile='/home/user/app_package/legacy_auth.pyc')"
    rm /home/user/app_package/legacy_auth.py

    # Create CSP rules
    cat << 'EOF' > /home/user/app_package/csp_rules.json
[
    {"id": "app1", "policy": "default-src 'self'; script-src 'self' 'unsafe-inline'"},
    {"id": "app2", "policy": "default-src 'self'; img-src https://*"},
    {"id": "app3", "policy": "default-src 'none'; script-src 'unsafe-eval'"},
    {"id": "app4", "policy": "default-src 'self'; font-src 'self'"}
]
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/app_package
    chmod -R 777 /home/user
