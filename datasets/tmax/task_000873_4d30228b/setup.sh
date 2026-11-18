#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/wordlist.txt
password
admin123
qwerty
cisco
juniper
network2023
letmein
root
EOF

    cat << 'EOF' > /home/user/auth_log.txt
[INFO] Failed login from 192.168.1.10 for user root with hash 5f4dcc3b5aa765d61d8327deb882cf99
[INFO] Failed login from 10.0.0.45 for user guest with hash 098f6bcd4621d373cade4e832627b4f6
[INFO] Failed login from 10.0.0.45 for user admin with hash 098f6bcd4621d373cade4e832627b4f6
[INFO] Failed login from 192.168.1.10 for user test with hash 5f4dcc3b5aa765d61d8327deb882cf99
[INFO] Failed login from 10.0.0.45 for user root with hash 098f6bcd4621d373cade4e832627b4f6
[INFO] Successful login from 192.168.1.2 for user admin with hash 73e20e36abeb4d193e64d60a5e2f6d2b
[INFO] Failed login from 10.0.0.45 for user sys with hash 098f6bcd4621d373cade4e832627b4f6
[INFO] Failed login from 10.0.0.45 for user db with hash 098f6bcd4621d373cade4e832627b4f6
[INFO] Failed login from 172.16.0.5 for user admin with hash 5f4dcc3b5aa765d61d8327deb882cf99
EOF

    chmod -R 777 /home/user
