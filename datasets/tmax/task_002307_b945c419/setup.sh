#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_configs

    cat << 'EOF' > /home/user/raw_configs/logs_A.json
[
  {"host_name": "srv-01", "event_time": "2023/10/01 14:00:00", "cfg_key": "max_conns", "cfg_val": 100},
  {"host_name": "srv-02", "event_time": "2023/10/01 14:05:00", "cfg_key": "timeout", "cfg_val": "30s"},
  {"host_name": "srv-01", "event_time": "2023/10/01 14:00:00", "cfg_key": "max_conns", "cfg_val": "100"}
]
EOF

    cat << 'EOF' > /home/user/raw_configs/logs_B.csv
server,date,key,value
srv-01,2023-10-01T14:00:00Z,max_conns,100
srv-03,2023-10-02T10:00:00Z,retries,3
srv-02,2023/10/01 14:05:00,timeout,30s
EOF

    chmod -R 777 /home/user
