#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/configs

    echo "network_timeout=30" > /home/user/configs/network.conf
    echo "db_host=localhost; db_port=5432" > /home/user/configs/database.conf
    echo "cache_size=1024; cache_type=redis" > /home/user/configs/cache.conf
    echo "log_level=debug" > /home/user/configs/logging.conf

    cat << 'EOF' > /home/user/config_log.txt
[UPDATE]
Date: 2023-10-01
Author: admin
Modified:
 - network.conf
 - logging.conf
[END]

[UPDATE]
Date: 2023-10-05
Author: dbadmin
Modified:
 - database.conf
 - cache.conf
[END]

[UPDATE]
Date: 2023-10-12
Author: sysadmin
Modified:
 - network.conf
 - cache.conf
[END]
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/configs /home/user/config_log.txt
    chmod -R 777 /home/user
