#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task
    apt-get install -y cron sqlite3 jq procps parallel

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create data directories and files
    mkdir -p /home/user/config_dumps

    cat << 'EOF' > /home/user/config_dumps/srv1.jsonl
{"server_id": "srv1", "timestamp": "2023-10-01T10:00:00Z", "config_data": "port=80\nmode=\u0061\u0063\u0074\u0069\u0076\u0065"}
{"server_id": "srv1", "timestamp": "2023-10-01T11:00:00Z", "config_data": "port=8080\nmode=\u0070\u0061\u0073\u0073\u0069\u0076\u0065"}
EOF

    cat << 'EOF' > /home/user/config_dumps/srv2.jsonl
{"server_id": "srv2", "timestamp": "2023-10-01T09:30:00Z", "config_data": "port=80\nmode=\u0061\u0063\u0074\u0069\u0076\u0065"}
{"server_id": "srv2", "timestamp": "2023-10-01T12:00:00Z", "config_data": "port=8080\nmode=\u0070\u0061\u0073\u0073\u0069\u0076\u0065"}
EOF

    cat << 'EOF' > /home/user/config_dumps/srv3.jsonl
{"server_id": "srv3", "timestamp": "2023-10-01T08:00:00Z", "config_data": "port=443\nmode=\u0061\u0063\u0074\u0069\u0076\u0065"}
EOF

    chown -R user:user /home/user/config_dumps

    # Start cron service (note: may need to be started at runtime depending on the environment)
    service cron start

    # Ensure correct permissions
    chmod -R 777 /home/user
