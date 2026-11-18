#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs
    mkdir -p /home/user/keys
    mkdir -p /home/user/secure_archive
    mkdir -p /home/user/network_policy

    cat << 'EOF' > /home/user/logs/login_attempts.csv
timestamp,ip_address,username,status
2023-10-01T10:00:00Z,10.0.0.5,admin,FAILED
2023-10-01T10:05:00Z,10.0.0.5,root,FAILED
2023-10-01T10:10:00Z,10.0.0.5,admin,FAILED
2023-10-01T10:15:00Z,10.0.0.5,test,FAILED
2023-10-01T10:20:00Z,10.0.0.9,user,FAILED
2023-10-01T10:25:00Z,10.0.0.9,user,SUCCESS
2023-10-01T10:30:00Z,192.168.1.100,admin,FAILED
2023-10-01T10:35:00Z,192.168.1.100,admin,FAILED
2023-10-01T10:40:00Z,192.168.1.100,admin,FAILED
2023-10-01T10:45:00Z,192.168.1.100,admin,FAILED
2023-10-01T10:50:00Z,192.168.1.100,admin,FAILED
2023-10-01T10:55:00Z,172.16.0.4,guest,FAILED
EOF

    cat << 'EOF' > /home/user/keys/audit.key
TnlqWk5MUkxNTHZ2Z2tqQ015dXZWeURpM1RzRGV4S1U=
EOF

    chmod -R 777 /home/user
