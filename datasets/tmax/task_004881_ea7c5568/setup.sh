#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak procps
    pip3 install pytest cryptography

    mkdir -p /app
    espeak -w /app/voicemail.wav "The payload passphrase is black mesa"

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/rogue_worker.py
import time, argparse
parser = argparse.ArgumentParser()
parser.add_argument('--salt', type=str)
args = parser.parse_args()
while True:
    time.sleep(60)
EOF

    cat << 'EOF' > /tmp/gen_enc.py
import os, json
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

passphrase = b"black mesa"
salt = b"7a8b9c0d1e2f3a4b"
kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=salt, iterations=100000, backend=default_backend())
key = kdf.derive(passphrase)

iv = os.urandom(16)
cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
encryptor = cipher.encryptor()

data = b'{"auth_token": "whiskey_tango_foxtrot_99", "listen_port": 8080}'
pad_len = 16 - (len(data) % 16)
data += bytes([pad_len]) * pad_len

ciphertext = encryptor.update(data) + encryptor.finalize()
with open('/home/user/evidence.enc', 'wb') as f:
    f.write(iv + ciphertext)
EOF

    python3 /tmp/gen_enc.py
    rm /tmp/gen_enc.py

    # Ensure the rogue worker process is started when a shell is spawned
    for rc in /etc/bash.bashrc /root/.bashrc /home/user/.bashrc; do
        echo 'pgrep -f rogue_worker.py >/dev/null || nohup python3 /home/user/rogue_worker.py --salt 7a8b9c0d1e2f3a4b >/dev/null 2>&1 &' >> "$rc"
    done

    # Fallback: wrapper around ps to ensure it's running if the test environment doesn't source bashrc
    mv /bin/ps /bin/ps_real
    cat << 'EOF' > /bin/ps
#!/bin/bash
if ! pgrep -f rogue_worker.py > /dev/null; then
    nohup python3 /home/user/rogue_worker.py --salt 7a8b9c0d1e2f3a4b >/dev/null 2>&1 &
    sleep 0.1
fi
exec /bin/ps_real "$@"
EOF
    chmod +x /bin/ps

    chmod -R 777 /home/user
    chmod -R 777 /app
