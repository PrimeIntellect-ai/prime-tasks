#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config_changes.csv
timestamp,server_id,config_key,config_value
2023-10-01T10:15:30Z,srvA,max_conn,100
2023-10-01T10:17:00Z,srvB,motd,"Hello
World"
2023-10-01T10:55:00Z,srvA,max_conn,200
2023-10-01T11:05:00Z,srvA,timeout,30
2023-10-01T11:06:00Z,srvA,timeout,40
2023-10-02T09:00:00Z,srvC,log_level,"DEBUG
VERBOSE"
2023-10-02T09:15:00Z,srvB,max_conn,150
EOF

    chmod -R 777 /home/user
