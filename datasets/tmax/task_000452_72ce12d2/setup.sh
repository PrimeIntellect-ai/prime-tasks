#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    mkdir -p /home/user/release/services

    cat << 'EOF' > /home/user/release/services/auth_1.0.0.json
{
  "name": "auth",
  "version": "1.0.0",
  "requires": {
    "db": ">= 1.0.0"
  },
  "routes": [
    {
      "path": "/login",
      "methods": ["POST"],
      "allowed_params": ["username", "password", "token"]
    }
  ]
}
EOF

    cat << 'EOF' > /home/user/release/services/auth_1.1.0.json
{
  "name": "auth",
  "version": "1.1.0",
  "requires": {
    "db": ">= 1.1.0"
  },
  "routes": [
    {
      "path": "/login",
      "methods": ["POST"],
      "allowed_params": ["username", "password", "token", "mfa"]
    }
  ]
}
EOF

    cat << 'EOF' > /home/user/release/services/db_1.0.0.json
{
  "name": "db",
  "version": "1.0.0",
  "requires": {
    "logger": ">= 1.0.0"
  },
  "routes": [
    {
      "path": "/data",
      "methods": ["GET", "POST"],
      "allowed_params": ["query", "limit"]
    }
  ]
}
EOF

    cat << 'EOF' > /home/user/release/services/db_1.1.0.json
{
  "name": "db",
  "version": "1.1.0",
  "requires": {
    "auth": ">= 1.1.0"
  },
  "routes": [
    {
      "path": "/data",
      "methods": ["GET", "POST"],
      "allowed_params": ["query", "limit", "offset"]
    }
  ]
}
EOF

    cat << 'EOF' > /home/user/release/services/logger_1.0.0.json
{
  "name": "logger",
  "version": "1.0.0",
  "requires": {},
  "routes": [
    {
      "path": "/logs",
      "methods": ["GET"],
      "allowed_params": ["date"]
    }
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
