#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/logs.jsonl
{"timestamp": "2023-10-01T10:00:15Z", "server": "srv-1", "cpu_load": 86.5, "msg": "status OK"}
{"timestamp": "2023-10-01T10:00:45Z", "server": "srv-2", "cpu_load": 92.3, "msg": "Error \u82"}
{"timestamp": "2023-10-01T10:01:10Z", "server": "srv-1", "cpu_load": 84.0, "msg": "test"}
{"timestamp": "2023-10-01T10:02:00Z", "server": "srv-3", "cpu_load": 95.1, "msg": "critical \uXYZ"}
{"timestamp": "2023-10-01T10:02:30Z", "server": "srv-4", "cpu_load": 80.0, "msg": "OK"}
EOF

    cat << 'EOF' > /home/user/servers.csv
srv-1,us-east
srv-2,us-west
srv-3,eu-central
srv-4,ap-south
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
