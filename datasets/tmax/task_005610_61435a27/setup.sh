#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo rustc
    pip3 install pytest cryptography

    mkdir -p /home/user/incident_workspace/encrypted
    mkdir -p /home/user/incident_workspace/decrypted

    cat << 'EOF' > /home/user/incident_workspace/crypto_params.txt
53757065725365637265744b6579313233343536373839303132333435363738
313233343536373839303132
EOF

    cat << 'EOF' > /tmp/web.log
10.0.0.55 - GET /index.html 200
10.0.0.55 - GET /assets/style.css 200
192.168.1.105 - GET /api/v1/health 200
192.168.1.105 - GET /api/v1/diagnostic?cmd=sudo%20/usr/bin/tar%20-cf%20/dev/null%20/dev/null%20--checkpoint=1%20--checkpoint-action=exec=/bin/sh 200
10.0.0.55 - GET /about 200
EOF

    cat << 'EOF' > /tmp/auth.log
May 10 11:55:01 server sshd[1234]: Accepted publickey for user1 from 10.0.0.55 port 55432 ssh2
May 10 12:01:45 server sudo: www-data : TTY=unknown ; PWD=/var/www/html ; USER=root ; COMMAND=/usr/bin/tar -cf /dev/null /dev/null --checkpoint=1 --checkpoint-action=exec=/bin/sh
May 10 12:05:00 server cron[111]: pam_unix(cron:session): session opened for user root by (uid=0)
EOF

    cat << 'EOF' > /tmp/encrypt.py
import sys
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

key = bytes.fromhex("53757065725365637265744b6579313233343536373839303132333435363738")
nonce = bytes.fromhex("313233343536373839303132")
aesgcm = AESGCM(key)

with open("/tmp/web.log", "rb") as f:
    web_data = f.read()

with open("/tmp/auth.log", "rb") as f:
    auth_data = f.read()

web_enc = aesgcm.encrypt(nonce, web_data, None)
auth_enc = aesgcm.encrypt(nonce, auth_data, None)

with open("/home/user/incident_workspace/encrypted/web.log.enc", "wb") as f:
    f.write(web_enc)

with open("/home/user/incident_workspace/encrypted/auth.log.enc", "wb") as f:
    f.write(auth_enc)
EOF

    python3 /tmp/encrypt.py
    rm /tmp/web.log /tmp/auth.log /tmp/encrypt.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
