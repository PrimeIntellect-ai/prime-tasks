#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ssh_keys
    mkdir -p /home/user/scripts

    cat << 'EOF' > /home/user/auth_logs.jsonl
{"ip": "192.168.1.10", "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhbGljZSJ9.signature1"}
{"ip": "10.0.0.5", "token": "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJhZG1pbl9iYWNrZG9vciJ9."}
{"ip": "192.168.1.11", "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJib2IifQ.signature2"}
{"ip": "10.0.0.6", "token": "eyJhbGciOiJOT05FIiwidHlwIjoiSldUIn0.eyJzdWIiOiJzeXN0ZW1fZGFlbW9uIn0."}
{"ip": "192.168.1.12", "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJjaGFybGllIn0.signature3"}
EOF

    touch /home/user/ssh_keys/id_rsa
    touch /home/user/ssh_keys/id_ed25519
    touch /home/user/ssh_keys/id_ecdsa
    touch /home/user/ssh_keys/public_key.pub

    echo '#!/bin/bash' > /home/user/scripts/backup.sh
    echo 'tar -czf /tmp/backup.tar.gz /home/user' >> /home/user/scripts/backup.sh

    echo '#!/bin/bash' > /home/user/scripts/cleanup.sh
    echo 'rm -rf /tmp/cache/*' >> /home/user/scripts/cleanup.sh

    chmod -R 777 /home/user

    # Restore specific permissions required by the task
    chmod 600 /home/user/ssh_keys/id_rsa
    chmod 644 /home/user/ssh_keys/id_ed25519
    chmod 660 /home/user/ssh_keys/id_ecdsa
    chmod 644 /home/user/ssh_keys/public_key.pub
    chmod 755 /home/user/scripts/backup.sh
    chmod 777 /home/user/scripts/cleanup.sh
