#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/investigation

    cat << 'EOF' > /tmp/setup.py
import os
import base64
import hashlib
import itertools

os.makedirs("/home/user/investigation", exist_ok=True)

# The password is 'byte'
password = b'byte'
password_hash = hashlib.sha256(password).hexdigest()

# Original cleartext script (before obfuscation)
cleartext_script = f"""
# Attacker Toolkit
# Decryption key is a 4-letter lowercase word.
# Target Hash (SHA-256): {password_hash}

def crypt(data, key):
    return bytes(a ^ b for a, b in zip(data, itertools.cycle(key)))
"""

# Obfuscate the dropper
encoded_script = base64.b64encode(cleartext_script.encode()).decode()
dropper_content = f"import base64\nexec(base64.b64decode('{encoded_script}').decode())\n"

with open("/home/user/investigation/dropper.py", "w") as f:
    f.write(dropper_content)

# Web logs with the SSTI payload
ssti_payload = "{" + "{" + "''." + "__class__.__mro__[1].__subclasses__()" + "}" + "}"
web_logs = f"""
192.168.1.10 - GET /index.html 200
10.0.0.5 - GET /login.php 200
172.16.0.88 - GET /profile?template={ssti_payload} 500
10.0.0.99 - POST /upload.php 201
"""

# Encrypt the logs using XOR with 'byte'
encrypted_logs = bytes(a ^ b for a, b in zip(web_logs.encode(), itertools.cycle(password)))

with open("/home/user/investigation/exfiltrated.dat", "wb") as f:
    f.write(encrypted_logs)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
