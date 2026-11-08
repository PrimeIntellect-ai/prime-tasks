#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/deps.json
{
  "nodes": [
    {"id": "app-api", "type": "app", "name": "app-api", "version": "1.0.0"},
    {"id": "app-worker", "type": "app", "name": "app-worker", "version": "1.0.0"},
    {"id": "app-legacy", "type": "app", "name": "app-legacy", "version": "1.0.0"},
    {"id": "app-admin", "type": "app", "name": "app-admin", "version": "2.0.0"},
    {"id": "lib-net", "type": "lib", "name": "lib-net", "version": "1.1.0"},
    {"id": "lib-auth", "type": "lib", "name": "lib-auth", "version": "1.2.0"},
    {"id": "lib-data", "type": "lib", "name": "lib-data", "version": "3.0.0"},
    {"id": "lib-utils", "type": "lib", "name": "lib-utils", "version": "1.5.0"},
    {"id": "lib-crypto", "type": "lib", "name": "lib-crypto", "version": "2.1.5"},
    {"id": "lib-db", "type": "lib", "name": "lib-db", "version": "1.0.5"},
    {"id": "lib-old", "type": "lib", "name": "lib-old", "version": "0.9.5"}
  ],
  "edges": [
    {"from": "app-api", "to": "lib-net"},
    {"from": "app-api", "to": "lib-auth"},
    {"from": "app-worker", "to": "lib-data"},
    {"from": "app-legacy", "to": "lib-old"},
    {"from": "app-admin", "to": "lib-utils"},
    {"from": "lib-net", "to": "lib-crypto"},
    {"from": "lib-auth", "to": "lib-crypto"},
    {"from": "lib-data", "to": "lib-db"}
  ]
}
EOF

    cat << 'EOF' > /home/user/rules.txt
lib-crypto < 2.2.0
lib-old < 1.0.0
lib-utils < 1.6.0
lib-db < 1.0.0
EOF

    cat << 'EOF' > /home/user/baseline.txt
app-legacy
app-worker
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
