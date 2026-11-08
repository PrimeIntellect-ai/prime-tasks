#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/server.py
import hashlib

# The secret is imported from a config file in the real app
from config import SECRET 

def generate_signature(url):
    # Weak signature generation
    return hashlib.md5((SECRET + url).encode()).hexdigest()

def verify_redirect(url, sig):
    return generate_signature(url) == sig

# Example route handler
# @app.route('/login')
# def login():
#     redirect_url = request.args.get('redirect')
#     sig = request.args.get('sig')
#     if verify_redirect(redirect_url, sig):
#         return redirect(redirect_url)
#     return "Invalid signature", 403
EOF

    cat << 'EOF' > /home/user/logs/debug.log
[2023-10-12 10:00:01] DEBUG: Starting server on port 8080
[2023-10-12 10:00:05] DEBUG: Loaded configuration.
[2023-10-12 10:00:05] WARNING: Secret key is set to 'auth_s3cr3t_2023!'. Do not use in production!
[2023-10-12 10:05:22] INFO: User 'admin' logged in successfully.
[2023-10-12 10:05:23] DEBUG: Redirecting to /dashboard. Signature: 4c3b90a6e87f620bd36db8fbfa59c3ab
EOF

    chmod -R 777 /home/user
