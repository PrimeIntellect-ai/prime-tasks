#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_auth.log
[2023-10-01T10:00:01] | IP: 192.168.1.50 | Port: 22 | User: admin@corp.com | Pass: P@ssw0rd123 | Status: Failed
[2023-10-01T10:00:05] | IP: 10.0.0.5 | Port: 8080 | User: test@demo.org | Pass: 123456 | Status: Failed
[2023-10-01T10:00:10] | IP: 10.0.0.5 | Port: 8080 | User: test@demo.org | Pass: password | Status: Failed
[2023-10-01T10:00:15] | IP: 10.0.0.5 | Port: 8080 | User: test@demo.org | Pass: admin | Status: Failed
[2023-10-01T10:00:20] | IP: 192.168.1.100 | Port: 22 | User: root@system.net | Pass: toor | Status: Success
[2023-10-01T10:01:00] | IP: 172.16.0.4 | Port: 443 | User: alice@wonderland.com | Pass: qweqwe | Status: Failed
[2023-10-01T10:01:05] | IP: 172.16.0.4 | Port: 443 | User: bob@wonderland.com | Pass: asdasd | Status: Failed
[2023-10-01T10:01:10] | IP: 172.16.0.4 | Port: 443 | User: charlie@wonderland.com | Pass: zxczxc | Status: Failed
[2023-10-01T10:01:15] | IP: 172.16.0.4 | Port: 443 | User: dave@wonderland.com | Pass: 111111 | Status: Failed
EOF

    chmod -R 777 /home/user
