#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/wordlist.txt
password123
admin
winter2022
compliance2023
securepass!
changeme
qwerty
EOF

cat << 'EOF' > /home/user/shadow_leak.txt
root:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
sysadmin:8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92
audit_usr:586b5155f8845fc868e4c76b97dbf6ab09c48b2a32eb511dd825cc2f107f918c
EOF

cat << 'EOF' > /home/user/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326
192.168.1.15 - - [10/Oct/2023:13:56:01 -0700] "GET /images/logo.png HTTP/1.1" 200 4011
192.168.1.42 - - [10/Oct/2023:13:58:11 -0700] "GET /admin/keys.zip HTTP/1.1" 403 212
10.0.0.55 - - [10/Oct/2023:14:01:14 -0700] "GET /admin/keys.zip HTTP/1.1" 200 8912
192.168.1.10 - - [10/Oct/2023:14:05:00 -0700] "GET /contact HTTP/1.1" 200 1022
EOF

# Use echo to avoid Apptainer parsing lines starting with % as section headers
echo "root    ALL=(ALL:ALL) ALL" > /home/user/sudoers_audit.txt
echo "%admin ALL=(ALL) ALL" >> /home/user/sudoers_audit.txt
echo "%sudo   ALL=(ALL:ALL) ALL" >> /home/user/sudoers_audit.txt
echo "audit_usr ALL=(root) NOPASSWD: /usr/bin/tar" >> /home/user/sudoers_audit.txt

chmod -R 777 /home/user
