#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/current_release.json
{
  "services": [
    {"name": "auth-api", "version": "2.1.0"},
    {"name": "payment-gateway", "version": "1.0.5"},
    {"name": "user-db", "version": "3.0.0-beta.2"},
    {"name": "notification-svc", "version": "1.1.0"}
  ]
}
EOF

    cat << 'EOF' > /home/user/target_release.json
{
  "services": [
    {"name": "auth-api", "version": "2.2.0"},
    {"name": "payment-gateway", "version": "1.0.5"},
    {"name": "user-db", "version": "3.0.0-beta.1"},
    {"name": "search-indexer", "version": "0.9.0"}
  ]
}
EOF

    chmod -R 777 /home/user
