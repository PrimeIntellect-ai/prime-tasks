#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/system_a.json
[
  {"timestamp": "2023-10-01T10:00:00Z", "msg": "DB connection timeout!", "severity": "HIGH"},
  {"timestamp": "2023-10-01T10:05:00Z", "msg": "Disk space low on /var", "severity": "MEDIUM"},
  {"timestamp": "2023-10-01T10:15:00Z", "msg": "CPU usage at 99%", "severity": "HIGH"},
  {"timestamp": "2023-10-01T10:18:00Z", "msg": "Network partition detected", "severity": "CRITICAL"}
]
EOF

    cat << 'EOF' > /home/user/data/system_b.csv
timestamp,message,severity
2023-10-01T10:01:00Z,"Db connection TIMEOUT!!",
2023-10-01T10:02:00Z,"Db connection timeout",
2023-10-01T10:08:00Z,"Db connection timeout",
2023-10-01T10:09:00Z,"Db connection timeout",
2023-10-01T10:12:00Z,"Memory leak detected in caching layer",CRITICAL
2023-10-01T10:16:00Z,"Cpu usage at 99 percent",
2023-10-01T10:20:00Z,"Completely unrelated error",
EOF

    chown -R user:user /home/user/data /home/user/output
    chmod -R 777 /home/user
