#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/configs

    cat << 'EOF' > /home/user/configs/dev.json
{"db_host": "localhost", "db_port": 5432, "debug": "true", "retry_count": 3, "api_url": "http://dev.api"}
EOF

    cat << 'EOF' > /home/user/configs/staging.json
{"db_host": "staging-db", "db_port": 5432, "debug": "true", "retry_count": 3, "api_url": "http://staging.api"}
EOF

    cat << 'EOF' > /home/user/configs/prod.json
{"db_host": "prod-db", "db_port": 5432, "debug": "false", "retry_count": 5, "api_url": "https://api.domain.com"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
