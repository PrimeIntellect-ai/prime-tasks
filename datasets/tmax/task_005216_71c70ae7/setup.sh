#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/manifest.json
{
  "services": [
    { "name": "auth-service", "lang": "rust", "port": 8081, "deps": ["db-migration"], "route": "/auth" },
    { "name": "api-gateway", "lang": "rust", "port": 8082, "deps": ["auth-service", "user-service"], "route": "/api" },
    { "name": "db-migration", "lang": "bash", "port": null, "deps": [], "route": null },
    { "name": "user-service", "lang": "rust", "port": 8083, "deps": ["db-migration"], "route": "/users" },
    { "name": "frontend", "lang": "node", "port": 3000, "deps": ["api-gateway"], "route": "/" }
  ]
}
EOF

    chmod -R 777 /home/user
