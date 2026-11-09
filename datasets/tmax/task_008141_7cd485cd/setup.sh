#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    mkdir -p /home/user/backups

    cat << 'EOF' > /home/user/backups/nodes.jsonl
{"id":"s1","type":"Server","datacenter":"us-east"}
{"id":"s2","type":"Server","datacenter":"us-east"}
{"id":"s3","type":"Server","datacenter":"eu-west"}
{"id":"s4","type":"Server","datacenter":"eu-west"}
{"id":"s5","type":"Server","datacenter":"ap-south"}
{"id":"s6","type":"Server","datacenter":"ap-south"}
{"id":"d1","type":"Database","datacenter":"us-east"}
EOF

    cat << 'EOF' > /home/user/backups/edges.jsonl
{"src":"s1","dst":"s2","rel":"NETWORK_LINK","weight":50}
{"src":"s2","dst":"s3","rel":"NETWORK_LINK","weight":20}
{"src":"s3","dst":"s4","rel":"NETWORK_LINK","weight":100}
{"src":"s1","dst":"d1","rel":"DB_CONNECTION","weight":500}
{"src":"s4","dst":"d1","rel":"NETWORK_LINK","weight":10}
{"src":"s5","dst":"s6","rel":"NETWORK_LINK","weight":300}
{"src":"s5","dst":"s2","rel":"NETWORK_LINK","weight":80}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
