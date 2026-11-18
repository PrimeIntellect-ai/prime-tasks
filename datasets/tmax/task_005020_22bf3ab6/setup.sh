#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/mail_spool
    cat << 'EOF' > /home/user/metrics.log
[2023-10-24 08:12:01] SERVICE=auth_service USAGE=10240 QUOTA=20480
[2023-10-24 08:13:00] SERVICE=cache_daemon USAGE=504800 QUOTA=500000
[2023-10-24 08:14:05] SERVICE=web_frontend USAGE=800 QUOTA=1000
[2023-10-24 08:15:10] SERVICE=queue_worker USAGE=1050000 QUOTA=1000000
[2023-10-24 08:16:00] SERVICE=db_indexer USAGE=4000 QUOTA=4000
EOF
    chmod 644 /home/user/metrics.log

    chmod -R 777 /home/user
