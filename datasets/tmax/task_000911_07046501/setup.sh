#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssh-server netcat-openbsd imagemagick tesseract-ocr tesseract-ocr-eng procps
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/.ssh
ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
cat /home/user/.ssh/id_rsa.pub > /home/user/.ssh/authorized_keys

ssh-keygen -t rsa -N "" -f /home/user/ssh_host_rsa_key
ssh-keygen -t ed25519 -N "" -f /home/user/ssh_host_ed25519_key

cat << 'EOF' > /home/user/sshd_config
Port 2222
HostKey /home/user/ssh_host_rsa_key
HostKey /home/user/ssh_host_ed25519_key
PidFile /home/user/sshd.pid
StrictModes no
AuthorizedKeysFile /home/user/.ssh/authorized_keys
EOF

mkdir -p /app
convert -background white -fill black -font Courier -pointsize 24 label:"SECURE RELAY CONFIGURATION\nAccess Control Lists:\nGroup: Admins -> alice, bob\nGroup: Devs -> charlie, dave\n\nTunnel Mappings:\nAdmins Target Port -> 5001\nDevs Target Port -> 5002" /app/architecture.png

cat << 'EOF' > /.singularity.d/env/99-start-services.sh
#!/bin/sh
if ! pgrep -f "sshd -p 2222" > /dev/null; then
    /usr/sbin/sshd -p 2222 -f /home/user/sshd_config
fi
if ! pgrep -f "nc -k -l 5001" > /dev/null; then
    nc -k -l 5001 > /tmp/backend_5001.log &
fi
if ! pgrep -f "nc -k -l 5002" > /dev/null; then
    nc -k -l 5002 > /tmp/backend_5002.log &
fi
EOF
chmod +x /.singularity.d/env/99-start-services.sh

mkdir -p /run/sshd
chmod 777 /run/sshd

chmod -R 777 /home/user
chmod 600 /home/user/.ssh/id_rsa
chmod 600 /home/user/.ssh/authorized_keys
chmod 700 /home/user/.ssh
