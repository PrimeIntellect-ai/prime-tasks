#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/wordlist.txt
admin
password
secret
123456
qwerty
EOF

    mkdir -p /home/user/repo

    cat << 'EOF' > /home/user/repo/app.conf
jwt=eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.e30.
custom_hash=134
EOF

    cat << 'EOF' > /home/user/repo/keys.txt
ssh-dss AAAAB3NzaC1kc3MAAACB...
EOF

    cat << 'EOF' > /home/user/repo/safe.txt
jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.
ssh-rsa AAAAB3NzaC1yc2E...
custom_hash=999
EOF

    chmod -R 777 /home/user
