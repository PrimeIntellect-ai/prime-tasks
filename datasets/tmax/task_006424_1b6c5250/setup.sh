#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo openssl faketime
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user/certs
mkdir -p /home/user/policy_builder

cat << 'EOF' > /home/user/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326
10.0.5.42 - - [10/Oct/2023:13:56:01 -0700] "GET /api/users?id=1 UNION SELECT username, password FROM users HTTP/1.1" 403 512
172.16.0.5 - - [10/Oct/2023:13:57:11 -0700] "POST /login HTTP/1.1" 200 44
10.0.5.42 - - [10/Oct/2023:13:58:22 -0700] "GET /api/data?q=' UNION SELECT 1,2,3-- HTTP/1.1" 403 512
203.0.113.88 - - [10/Oct/2023:14:01:05 -0700] "GET /search?q=UNION SELECT * FROM information_schema.tables HTTP/1.1" 403 512
EOF

# Use faketime to create expired certificates
faketime '2020-01-01' openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -keyout /tmp/key1.pem -out /home/user/certs/port_8081.pem -subj "/CN=expired.local"
faketime '2020-01-01' openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -keyout /tmp/key2.pem -out /home/user/certs/port_9000.pem -subj "/CN=old.local"

# Create valid certificates
openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -keyout /tmp/key3.pem -out /home/user/certs/port_8443.pem -subj "/CN=valid.local"
openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -keyout /tmp/key4.pem -out /home/user/certs/port_443.pem -subj "/CN=secure.local"

chmod -R 777 /home/user
