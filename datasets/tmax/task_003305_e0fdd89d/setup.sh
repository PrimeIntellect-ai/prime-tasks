#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/node1.jsonl
{"event": "update", "config_key": "network.proxy.url", "config_value": "http\u003a\u002f\u002fproxy.local\u003a8080", "timestamp": 1679921020}
{"event": "update", "config_key": "system.memory", "config_value": "1024", "timestamp": 1679921021}
{"event": "update", "config_key": "network.timeout", "config_value": "30", "timestamp": 1679921022}
EOF

    cat << 'EOF' > /home/user/logs/node2.jsonl
{"event": "update", "config_key": "network.proxy.url", "config_value": "http\u003a\u002f\u002fproxy.local\u003a8080", "timestamp": 1679921023}
{"event": "update", "config_key": "network.dns.primary", "config_value": "8.8.8.8", "timestamp": 1679921024}
{"event": "update", "config_key": "app.workers", "config_value": "4", "timestamp": 1679921025}
{"event": "update", "config_key": "network.host.tags", "config_value": "region\u003deast\u002cenv\u003dprod", "timestamp": 1679921026}
EOF

    cat << 'EOF' > /home/user/logs/node3.jsonl
{"event": "update", "config_key": "network.dns.primary", "config_value": "8.8.8.8", "timestamp": 1679921027}
{"event": "update", "config_key": "network.dns.secondary", "config_value": "8.8.4.4", "timestamp": 1679921028}
EOF

    chown -R user:user /home/user/logs
    chmod -R 777 /home/user
