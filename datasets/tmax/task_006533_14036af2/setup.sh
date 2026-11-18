#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/old_state.txt
SERVICE[web] param:timeout | val:30s // default
SERVICE[web] param:max_connections | val: "100" // peak
SERVICE[db] param:auth_mode | val: SCRAM-SHA-256
SERVICE[db] param:cache | val: " Redis_Cache-Tier "
SERVICE[db] param:legacy_flag | val: True // removing soon
SERVICE[api] param:rate_limit | val: 1000-req_per_min
EOF

    cat << 'EOF' > /home/user/new_state.txt
SERVICE[web] param:timeout | val:  30s  // default
SERVICE[web] param:max_connections | val: "150" // increased for peak
SERVICE[web] param:retry_policy | val: expo-backoff
SERVICE[db] param:auth_mode | val: scram_sha_256 // normalized auth
SERVICE[db] param:cache | val: "redis cache tier"
SERVICE[cache] param:engine | val: memcached
SERVICE[api] param:rate_limit | val: " 1000  req per min "
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
