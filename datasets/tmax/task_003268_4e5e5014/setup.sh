#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip
    pip3 install pytest

    mkdir -p /home/user/backups
    mkdir -p /tmp/v1/system /tmp/v1/app
    mkdir -p /tmp/v2/system /tmp/v2/app
    mkdir -p /tmp/v3/system /tmp/v3/app

    # v1 files
    cat << 'EOF' > /tmp/v1/system/network.ini
[interface]
eth0=dhcp
mtu=1500
EOF
    cat << 'EOF' > /tmp/v1/app/config.json
{"feature_flag": false, "retries": 3}
EOF

    # v2 files
    cat << 'EOF' > /tmp/v2/system/network.ini
[interface]
eth0=static
mtu=1500
EOF
    cat << 'EOF' > /tmp/v2/app/config.json
{"feature_flag": true, "retries": 3}
EOF

    # v3 files
    cat << 'EOF' > /tmp/v3/system/network.ini
[interface]
eth0=static
mtu=9000
EOF
    cat << 'EOF' > /tmp/v3/app/config.json
{"feature_flag": true, "retries": 5}
EOF
    cat << 'EOF' > /tmp/v3/app/db.ini
[mysql]
host=localhost
port=3306
EOF

    # Create archives
    cd /tmp/v1 && tar -czf /home/user/backups/v1.tar.gz .
    cd /tmp/v2 && zip -r /home/user/backups/v2.zip .
    cd /tmp/v3 && tar -czf /home/user/backups/v3.tar.gz .
    rm -rf /tmp/v1 /tmp/v2 /tmp/v3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
