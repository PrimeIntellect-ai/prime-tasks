#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/investigation/logs

    head -c 1024 /dev/urandom > /home/user/investigation/mem_dump.bin
    echo -n "http://cmd.c2.malware.local/download/payload.sh" >> /home/user/investigation/mem_dump.bin
    head -c 1024 /dev/urandom >> /home/user/investigation/mem_dump.bin

    cat << 'EOF' > /home/user/investigation/logs/api.log
2024-05-10T08:14:01Z INFO API service started
2024-05-10T08:14:03Z INFO Received job request from worker
2024-05-10T08:14:07Z ERROR EnvironmentError: WORKER_AUTH_TOKEN not set
2024-05-10T08:14:08Z CRITICAL CRASH
EOF

    cat << 'EOF' > /home/user/investigation/logs/db.log
2024-05-10T08:14:02Z INFO DB connection established
2024-05-10T08:14:04Z INFO Queried configuration table
2024-05-10T08:14:06Z WARN Retrying failed query
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
