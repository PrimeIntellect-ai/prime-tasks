#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl
pip3 install pytest

mkdir -p /home/user
cd /home/user

# Generate certificate
openssl req -x509 -newkey rsa:2048 -keyout /tmp/key.pem -out /tmp/server.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=malicious-update-server.local" 2>/dev/null
cat /tmp/server.crt | base64 > /home/user/payload.b64
rm -f /tmp/key.pem /tmp/server.crt

# Generate access.log
cat << 'EOF' > /home/user/access.log
192.168.1.50 - - [10/Oct/2023:13:55:36 -0700] "GET /login.php?user=admin%27%20OR%201%3D1-- HTTP/1.1" 200 1024
10.0.0.5 - - [10/Oct/2023:13:56:00 -0700] "GET /login.php?user=admin%27%20OR%201%3D1-- HTTP/1.1" 403 512
172.16.0.2 - - [10/Oct/2023:13:57:00 -0700] "GET /search.php?q=%3Cscript%3Ealert(1)%3C/script%3E HTTP/1.1" 200 2048
192.168.1.100 - - [10/Oct/2023:14:00:00 -0700] "GET /index.php?id=-1%20UNION%20SELECT%20password%20FROM%20users HTTP/1.1" 200 1024
8.8.8.8 - - [10/Oct/2023:14:05:00 -0700] "GET /index.php?id=1 HTTP/1.1" 200 500
192.168.1.50 - - [10/Oct/2023:14:10:00 -0700] "GET /login.php?user=test%27%20or%201%3d1-- HTTP/1.1" 200 1024
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/payload.b64 /home/user/access.log
chmod -R 777 /home/user
