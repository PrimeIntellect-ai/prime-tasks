#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar rsync
    pip3 install pytest

    mkdir -p /home/user/configs
    mkdir -p /home/user/remote_backup

    cat << 'EOF' > /home/user/configs/app1.conf
# App 1 Configuration
PORT=8080
DB_URL=postgres://admin:secretPass123@10.0.0.5:5432/mydb
CACHE_URL=redis://10.0.0.6:6379/0
ENABLE_FEATURE_X=true
EOF

    cat << 'EOF' > /home/user/configs/app2.conf
# App 2 Configuration
DB_URL=mysql://root:pass@192.168.1.100:3306/db2
SOME_OTHER_VAR=123
EOF

    cat << 'EOF' > /home/user/configs/app3.conf
# App 3 Configuration
CACHE_URL=memcached://172.16.0.4:11211/1
WORKERS=4
EOF

    cat << 'EOF' > /home/user/configs/app4.conf
# App 4 Configuration (Edge case: no auth)
DB_URL=mongodb://db.internal.net:27017/nosql
EOF

    cd /home/user
    tar -czf configs.tar.gz configs
    rm -rf /home/user/configs

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/configs.tar.gz /home/user/remote_backup
    chmod -R 777 /home/user
