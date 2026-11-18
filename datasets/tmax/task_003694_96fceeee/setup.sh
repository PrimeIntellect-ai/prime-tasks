#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config_updates.log
[2023-10-15 08:00:00] srv-01 WORKER_THREADS=4
[2023-10-15 08:05:00] srv-02 WORKER_THREADS=8
[2023-10-15 08:10:00] srv-01 DB_HOST=primary-db
[2023-10-15 08:15:00] srv-03 CACHE_SIZE=1024
[2023-10-15 08:15:00] srv-03 CACHE_SIZE=1024
[2023-10-15 08:20:00] srv-01 WORKER_THREADS=16
[2023-10-15 08:25:00] srv-02 DB_HOST=replica-db
[2023-10-15 08:30:00] srv-01 DB_HOST=primary-db-v2
[2023-10-15 08:35:00] srv-03 WORKER_THREADS=8
[2023-10-15 08:40:00] srv-02 WORKER_THREADS=8
EOF

    chmod -R 777 /home/user
