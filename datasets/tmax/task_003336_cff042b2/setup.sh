#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev make openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create sshd_config
    cat << 'EOF' > /home/user/sshd_config
# SSH config
Port 22
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication no
EOF

    # Create certs
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/ca.key -out /home/user/ca.pem -days 365 -nodes -subj "/CN=TestCA"
    openssl req -newkey rsa:2048 -keyout /home/user/server.key -out /home/user/server.csr -nodes -subj "/CN=TestServer"
    openssl x509 -req -in /home/user/server.csr -CA /home/user/ca.pem -CAkey /home/user/ca.key -CAcreateserial -out /home/user/server.pem -days 365

    # Create auth.log
    cat << 'EOF' > /home/user/auth.log
Jan 10 10:00:01 server sshd[1234]: Failed password for root from 10.9.8.7 port 22 ssh2
Jan 10 10:05:01 server sshd[1235]: Failed password for admin from 10.9.8.7 port 22 ssh2
Jan 10 10:10:01 server sshd[1236]: Failed password for invalid user test from 172.16.5.5 port 22 ssh2
Jan 10 10:15:01 server sshd[1237]: Accepted publickey for user from 192.168.1.1 port 22 ssh2
Jan 10 10:20:01 server sshd[1238]: Failed password for root from 10.9.8.7 port 22 ssh2
Jan 10 10:25:01 server sshd[1239]: Failed password for root from 172.16.5.5 port 22 ssh2
Jan 10 10:30:01 server sshd[1240]: Failed password for root from 10.9.8.7 port 22 ssh2
Jan 10 10:35:01 server sshd[1241]: Failed password for root from 172.16.5.5 port 22 ssh2
Jan 10 10:40:01 server sshd[1242]: Failed password for root from 192.168.1.100 port 22 ssh2
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
