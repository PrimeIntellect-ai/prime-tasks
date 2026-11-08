#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssh-server imagemagick fonts-liberation
pip3 install pytest

mkdir -p /app
ssh-keygen -t rsa -N "ShadowKey99" -f /app/id_rsa

useradd -m -s /bin/bash user || true
mkdir -p /home/user/.ssh
cp /app/id_rsa.pub /home/user/.ssh/authorized_keys
chmod 700 /home/user/.ssh
chmod 600 /home/user/.ssh/authorized_keys
chown -R user:user /home/user/.ssh

mkdir -p /var/run/sshd
ssh-keygen -A

mkdir -p /var/opt
echo "FLAG{evasion_successful}" > /var/opt/flag.txt

convert -size 800x100 xc:black -font Liberation-Sans -pointsize 24 -fill white -draw "text 10,50 'PID 1042: python3 backup.py --ssh-passphrase 536861646f774b65793939'" /app/leak.png

# Ensure SSH server runs when the container is executed
echo '#!/bin/bash\nservice ssh start\nexec "$@"' > /entrypoint.sh
chmod +x /entrypoint.sh

chmod -R 777 /home/user
