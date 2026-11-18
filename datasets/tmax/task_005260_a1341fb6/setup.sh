#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest requests

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/waf_logs.json
[
  {"ip": "192.168.1.5", "action": "allowed", "user_agent": "Mozilla/5.0"},
  {"ip": "10.0.0.2", "action": "blocked", "user_agent": "curl/7.68.0"},
  {"ip": "10.0.0.3", "action": "blocked", "user_agent": "Nmap Scripting Engine"},
  {"ip": "172.16.0.4", "action": "allowed", "user_agent": "curl/7.68.0"},
  {"ip": "10.0.0.5", "action": "blocked", "user_agent": "curl/7.68.0"},
  {"ip": "10.0.0.6", "action": "blocked", "user_agent": "sqlmap/1.5.8.2#dev"}
]
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
