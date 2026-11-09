#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/.ssh_mock
mkdir -p /home/user/audit

cat << 'EOF' > /home/user/auth.log
Jan 12 10:00:01 server sshd[1024]: Failed password for root from 10.0.0.5 port 22 ssh2
Jan 12 10:01:01 server sshd[1025]: Failed password for root from 10.0.0.5 port 22 ssh2
Jan 12 10:02:01 server sshd[1026]: Failed password for root from 10.0.0.5 port 22 ssh2
Jan 12 10:03:01 server sshd[1027]: Failed password for root from 10.0.0.5 port 22 ssh2
Jan 12 10:04:01 server sshd[1028]: Failed password for user1 from 10.0.0.5 port 22 ssh2
Jan 12 10:05:01 server sshd[1029]: Failed password for admin from 172.16.0.2 port 22 ssh2
Jan 12 10:06:01 server sshd[1030]: Failed password for admin from 172.16.0.2 port 22 ssh2
Jan 12 10:07:01 server sshd[1031]: Failed password for admin from 172.16.0.2 port 22 ssh2
Jan 12 10:08:01 server sshd[1032]: Failed password for admin from 172.16.0.2 port 22 ssh2
Jan 12 10:09:01 server sshd[1033]: Failed password for root from 192.168.1.50 port 22 ssh2
Jan 12 10:10:01 server sshd[1034]: Failed password for root from 192.168.1.50 port 22 ssh2
Jan 12 10:11:01 server sshd[1035]: Accepted publickey for root from 10.1.1.1 port 22 ssh2
Jan 12 10:12:01 server sshd[1036]: Failed password for admin from 10.0.0.8 port 22 ssh2
EOF

touch /home/user/.ssh_mock/id_rsa.key
touch /home/user/.ssh_mock/id_ed25519.key
touch /home/user/.ssh_mock/id_ecdsa.key
touch /home/user/.ssh_mock/id_rsa.pub
touch /home/user/.ssh_mock/config

cat << 'EOF' > /home/user/audit_sshd_config
# This is a mock sshd_config
Port 22
ListenAddress 0.0.0.0

# Authentication:
PermitRootLogin yes
MaxAuthTries 6

# To disable tunneled clear text passwords, change to no here!
PasswordAuthentication yes
PermitEmptyPasswords no

X11Forwarding yes
EOF

chown -R user:user /home/user
chmod -R 777 /home/user

# Fix specific permissions that were overwritten by the chmod -R 777 above
chmod 644 /home/user/.ssh_mock/id_rsa.key
chmod 600 /home/user/.ssh_mock/id_ed25519.key
chmod 777 /home/user/.ssh_mock/id_ecdsa.key
chmod 644 /home/user/.ssh_mock/id_rsa.pub
chmod 644 /home/user/.ssh_mock/config
