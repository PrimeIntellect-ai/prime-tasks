#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/server_logs
cat << 'EOF' > /home/user/server_logs/auth.log
Jan 12 10:00:01 server sshd[1024]: Failed publickey for admin from 10.0.0.5 port 54321 ssh2
Jan 12 10:00:02 server sshd[1024]: Failed publickey for admin from 10.0.0.5 port 54321 ssh2
Jan 12 10:00:03 server sshd[1024]: Failed publickey for admin from 10.0.0.5 port 54321 ssh2
Jan 12 10:00:04 server sshd[1024]: Accepted publickey for admin from 10.0.0.5 port 54321 ssh2
Jan 12 10:05:01 server sshd[1025]: Failed publickey for admin from 192.168.1.100 port 12345 ssh2
Jan 12 10:05:02 server sshd[1025]: Failed publickey for admin from 192.168.1.100 port 12345 ssh2
Jan 12 10:05:03 server sshd[1025]: Accepted publickey for admin from 192.168.1.100 port 12345 ssh2
Jan 12 10:10:01 server sshd[1026]: Failed publickey for admin from 172.16.0.50 port 33333 ssh2
Jan 12 10:10:02 server sshd[1026]: Failed publickey for admin from 172.16.0.50 port 33333 ssh2
Jan 12 10:10:03 server sshd[1026]: Failed publickey for admin from 172.16.0.50 port 33333 ssh2
Jan 12 10:10:04 server sshd[1027]: Connection closed by 172.16.0.50 port 33333
Jan 12 10:10:05 server sshd[1026]: Accepted publickey for admin from 172.16.0.50 port 33333 ssh2
Jan 12 10:15:01 server sshd[1028]: Failed publickey for admin from 10.1.1.1 port 44444 ssh2
Jan 12 10:15:02 server sshd[1028]: Failed publickey for admin from 10.1.1.1 port 44444 ssh2
Jan 12 10:15:03 server sshd[1028]: Failed publickey for admin from 10.1.1.1 port 44444 ssh2
Jan 12 10:15:04 server sshd[1028]: Accepted publickey for admin from 10.1.1.1 port 44444 ssh2
EOF

mkdir -p /home/user/home_backup/alice/.ssh
mkdir -p /home/user/home_backup/bob/.ssh
mkdir -p /home/user/home_backup/charlie/.ssh
mkdir -p /home/user/home_backup/eve/keys

echo "-----BEGIN OPENSSH PRIVATE KEY-----" > /home/user/home_backup/charlie/.ssh/id_rsa
echo "-----BEGIN RSA PRIVATE KEY-----" > /home/user/home_backup/alice/.ssh/id_rsa
echo "-----BEGIN OPENSSH PRIVATE KEY-----" > /home/user/home_backup/bob/.ssh/id_rsa
echo "-----BEGIN OPENSSH PRIVATE KEY-----" > /home/user/home_backup/eve/keys/id_rsa

chmod -R 777 /home/user

chmod 700 /home/user/home_backup/charlie/.ssh
chmod 600 /home/user/home_backup/charlie/.ssh/id_rsa
chmod 700 /home/user/home_backup/alice/.ssh
chmod 644 /home/user/home_backup/alice/.ssh/id_rsa
chmod 755 /home/user/home_backup/bob/.ssh
chmod 600 /home/user/home_backup/bob/.ssh/id_rsa
chmod 660 /home/user/home_backup/eve/keys/id_rsa
