#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc tar
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/backup_source
cat << 'EOF' > /home/user/backup_source/mail_config.conf
LISTEN_IP=0.0.0.0
SMTP_PORT=2525
MAX_CONNECTIONS=100
ENABLE_TLS=yes
EOF

cat << 'EOF' > /home/user/backup_source/vm_settings.json
{
  "qemu_binary": "/usr/bin/qemu-system-x86_64",
  "memory": "2048M",
  "vnc_port": 5900
}
EOF

cat << 'EOF' > /home/user/backup_source/postfix_main.cf
myhostname = mail.example.com
mydomain = example.com
myorigin = $mydomain
EOF

cat << 'EOF' > /home/user/backup_source/aliases
postmaster: root
abuse: postmaster
EOF

cd /home/user/backup_source
tar -czf /home/user/backup_data.tar.gz *
cd /home/user
rm -rf /home/user/backup_source

chmod -R 777 /home/user
