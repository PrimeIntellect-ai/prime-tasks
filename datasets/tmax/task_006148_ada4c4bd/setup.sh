#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/intercepted_traffic.txt
POST /login HTTP/1.1
Host: internal.corp
User-Agent: curl/7.68.0
Accept: */*
Cookie: Session-Auth=eyJoYXNoIjogIjA4NWVhMzBiZDYxNTE2ZTkxZWE2YjY2ZDRkYzVhMmJjIn0=
Content-Length: 0
Content-Type: application/x-www-form-urlencoded
EOF

    cat << 'EOF' > /home/user/wordlist.txt
admin123
password
compliance2023
secure_pass
audit_trail_123
qwerty
EOF

    cat << 'EOF' > /home/user/sshd_config
# SSH Audit config
Port 22
Protocol 2
PermitRootLogin yes
MaxAuthTries 3
PubkeyAuthentication yes
PasswordAuthentication yes
#X11Forwarding no
EOF

    chmod -R 777 /home/user
