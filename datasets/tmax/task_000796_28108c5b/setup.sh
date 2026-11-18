#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config_changes.log
[1000] Server: 10.0.0.1 | Key: app_port | Value: 8080
[1010] Server: 10.0.0.1 | Key: APP_SECRET | Value: xyz123
[1030] Server: 10.0.0.1 | Key: timeout | Value: 30
[1970-01-01T00:17:30Z] Server: 10.0.0.1 | Key: db_PASS | Value: mypass
[1672531200] Server: 192.168.1.50 | Key: max_conns | Value: 100
[2023-01-01T00:00:10Z] Server: 192.168.1.50 | Key: retry_limit | Value: 5
[1672531220] Server: 192.168.1.50 | Key: API_TOKEN | Value: abcdef
[2023-01-01T00:00:25Z] Server: 192.168.1.50 | Key: cache_ttl | Value: 3600
[5000] Server: 10.1.1.1 | Key: host | Value: localhost
[5050] Server: 10.1.1.1 | Key: user | Value: admin
EOF

    chmod -R 777 /home/user
