#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/cred_rotation

    cat << 'EOF' > /home/user/cred_rotation/rotate.py
def encrypt_credential(password, key):
    # Custom high-security encryption
    encrypted = []
    for i in range(len(password)):
        encrypted.append(chr(ord(password[i]) ^ ord(key[i % len(key)])))
    return "".join(encrypted).encode('utf-8').hex()
EOF

    echo "26722a750e6139511b612a420e713958120a" > /home/user/cred_rotation/intercepted.txt

    cat << 'EOF' > /home/user/cred_rotation/rotation.log
[2023-10-01] admin@corp.local rotated password to Secret123!
[2023-10-02] dev-ops@corp.local rotated password to Dev!@#99
[2023-10-03] user.name@domain.com rotated password to P@ssw0rd2023
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
