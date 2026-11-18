#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip john
    pip3 install pytest

    mkdir -p /home/user/app

    echo -n "43ec317a001ce87ecb2e956e18413b86" > /home/user/admin.hash

    cat << 'EOF' > /home/user/wordlist.txt
password
admin
sunshine
qwerty
iloveyou
EOF

    cat << 'EOF' > /home/user/app/login.py
def get_redirect_url(next_param):
    return next_param
EOF

    echo '{"token": "super_secret_token_123"}' > /home/user/app/config.json
    chmod 777 /home/user/app/config.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
