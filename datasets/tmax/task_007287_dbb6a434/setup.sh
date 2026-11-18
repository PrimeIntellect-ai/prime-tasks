#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/raw_logs

    cat << 'EOF' > /home/user/raw_logs/cluster_a.csv
timestamp,cpu_usage,memory_usage
1000,10.0,100
3000,,120
5000,30.0,140
EOF

    cat << 'EOF' > /home/user/raw_logs/cluster_b.json
[
  {"t": 2000, "cpu": 15.0, "mem": null},
  {"t": 4000, "cpu": 25.0, "mem": 130},
  {"t": 6000, "cpu": 35.0, "mem": null}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
