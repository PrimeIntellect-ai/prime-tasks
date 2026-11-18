#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ openssl faketime
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/certs /home/user/.ssh

    cat << 'EOF' > /home/user/traffic.log
1690000000 10.0.0.5 80 GET / HTTP/1.1
1690000010 192.168.1.100 443 User-Agent: () { :; }; echo vulnerable
1690000020 10.0.0.8 22 SSH-2.0-OpenSSH
1690000030 172.16.0.50 80 GET /index.php?id=1 UNION SELECT null, null--
1690000040 10.0.0.12 8080 POST /login admin:admin
EOF

    cat << 'EOF' > /home/user/signatures.txt
() { :; };
UNION SELECT
admin:admin
EOF

    # Good cert (Valid, RSA 2048)
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/k1.pem -out /home/user/certs/cert_good.pem -days 3650 -nodes -subj "/CN=good.local"

    # Expired cert (Expired, RSA 2048) - using faketime to generate a certificate in the past
    faketime '2020-01-01 00:00:00' openssl req -x509 -newkey rsa:2048 -keyout /tmp/k2.pem -out /home/user/certs/cert_expired.pem -days 365 -nodes -subj "/CN=expired.local"

    # Weak key cert (Valid, RSA 1024)
    openssl req -x509 -newkey rsa:1024 -keyout /tmp/k3.pem -out /home/user/certs/cert_weak.pem -days 3650 -nodes -subj "/CN=weak.local"

    cat << 'EOF' > /home/user/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQ... user@10.0.0.5
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQ... attacker@192.168.1.100
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQ... user@10.0.0.8
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQ... badguy@172.16.0.50
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQ... lazy@10.0.0.12
EOF

    chmod -R 777 /home/user
