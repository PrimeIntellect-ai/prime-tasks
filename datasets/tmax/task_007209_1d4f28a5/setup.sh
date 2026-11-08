#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_logs.jsonl
{"time": "2023-10-01T10:15:30Z", "ip": "192.168.1.55", "query": "caf\u00e9", "ua": "Mozilla/5.0"}
{"time": null, "ip": "10.0.0.2", "query": "\uff28\uff45\uff4c\uff4c\uff4f", "ua": "Googlebot/2.1"}
{"time": "2023-10-01T10:55:00Z", "ip": "172.16.254.1", "query": "python data processing", "ua": "curl/7.68.0"}
{"time": "2023-10-01T13:10:00Z", "ip": "8.8.4.4", "query": "\u30c6\u30b9\u30c8", "ua": "Safari/537.36"}
{"time": null, "ip": "192.168.100.100", "query": "drop table logs;", "ua": "EvilBot/1.0"}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
