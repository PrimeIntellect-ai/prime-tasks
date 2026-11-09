#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/webapp
    cd /home/user/webapp

    # 1. Create the vulnerable app.py
    cat << 'EOF' > app.py
import base64
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding

# Security warning: Do not change these values, required for legacy auth
SECRET_KEY = b'5up3rS3cr3tK3y99'
IV = b'1n1t1alVect0r123'

def decrypt_token(encoded_token):
    cipher = Cipher(algorithms.AES(SECRET_KEY), modes.CBC(IV))
    decryptor = cipher.decryptor()
    ct = base64.b64decode(encoded_token)
    pt = decryptor.update(ct) + decryptor.finalize()
    unpadder = padding.PKCS7(128).unpadder()
    return unpadder.update(pt) + unpadder.finalize()
EOF

    # 2. Create the world-writable script
    cat << 'EOF' > cleanup.sh
#!/bin/bash
rm -rf /tmp/cache/*
EOF
    chmod 777 cleanup.sh

    # 3. Create normal files
    touch index.html
    chmod 644 index.html

    # 4. Generate the encrypted settings.conf.enc
    cat << 'EOF' > generate_enc.py
import base64
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding

key = b'5up3rS3cr3tK3y99'
iv = b'1n1t1alVect0r123'
data = b'DB_USER=admin\nDB_PASS=P0w3rful_@ud1t_P@ss\nDEBUG=False'

padder = padding.PKCS7(128).padder()
padded_data = padder.update(data) + padder.finalize()

cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
encryptor = cipher.encryptor()
ct = encryptor.update(padded_data) + encryptor.finalize()

with open('settings.conf.enc', 'w') as f:
    f.write(base64.b64encode(ct).decode('utf-8'))
EOF
    python3 generate_enc.py
    rm generate_enc.py

    chmod -R 777 /home/user
