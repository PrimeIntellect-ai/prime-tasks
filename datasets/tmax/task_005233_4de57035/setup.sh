#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip coreutils
    pip3 install pytest

    mkdir -p /home/user/raw_logs/app1/prod
    mkdir -p /home/user/raw_logs/app1/dev
    mkdir -p /home/user/raw_logs/app2/prod
    mkdir -p /home/user/raw_logs/app2/staging
    mkdir -p /home/user/archive

    cat << 'EOF' | gzip > /home/user/raw_logs/app1/prod/access.log.gz
INFO User logged in IP: 192.168.1.100
DEBUG Connection established
ERROR Failed to load module
INFO Activity from IP: 10.0.0.5
EOF

    cat << 'EOF' | gzip > /home/user/raw_logs/app1/dev/access.log.gz
INFO Dev user logged in IP: 127.0.0.1
EOF

    {
      for i in {1..2000}; do
        echo "INFO Normal operation $i"
        echo "DEBUG Checking memory state $i"
        echo "WARN High load from IP: 172.16.254.1"
      done
    } | gzip > /home/user/raw_logs/app2/prod/system.log.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
