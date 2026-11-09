#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip zip unzip openssl faketime openssh-client
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user/workspace
mkdir -p /home/user/.ssh

# Wordlist
cat << 'EOF' > /home/user/workspace/wordlist.txt
apple
banana
dragonfly2023
password
123456
qwerty
admin
EOF

# SSHD config
cat << 'EOF' > /tmp/sshd_config
Port 22
PermitRootLogin no
PermitEmptyPasswords yes
PasswordAuthentication yes
EOF

# Certificates
openssl req -x509 -newkey rsa:2048 -keyout /tmp/valid.key -out /tmp/valid.crt -days 3650 -nodes -subj "/CN=valid.internal.corp"
faketime '2010-01-01' openssl req -x509 -newkey rsa:2048 -keyout /tmp/expired.key -out /tmp/expired.crt -days 365 -nodes -subj "/CN=legacy.internal.corp"
cat /tmp/valid.crt /tmp/expired.crt > /tmp/chain.pem

# DB backup log
cat << 'EOF' > /tmp/db_backup.log
Starting backup...
User AKIA1234567890ABCDEF logged in.
Processing table 1...
Error: AKIABBBBBBBBBBBBBBBB not found.
Done.
EOF

# SSH key
ssh-keygen -t rsa -N "" -f /tmp/id_rsa

# Zip them up
cd /tmp
zip -P dragonfly2023 /home/user/workspace/secret_backup.zip chain.pem sshd_config db_backup.log id_rsa

# Clean up tmp
rm /tmp/chain.pem /tmp/sshd_config /tmp/db_backup.log /tmp/id_rsa /tmp/id_rsa.pub /tmp/valid.* /tmp/expired.*

chmod -R 777 /home/user
chmod 700 /home/user/.ssh
