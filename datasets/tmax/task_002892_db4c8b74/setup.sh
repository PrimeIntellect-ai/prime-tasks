#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/config_logs.csv
timestamp,service_name,user_email,changes_count
1700000000,nginx,admin@acme.corp,5
1700000060,sshd,root@acme.corp,
1700000120,nginx,dev@acme.corp,10
1700000180,postgres,dba@acme.corp,
1700000240,redis,cache@acme.corp,3
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
