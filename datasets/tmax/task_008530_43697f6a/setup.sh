#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget g++ libssl-dev
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    wget -qO /home/user/json.hpp https://github.com/nlohmann/json/releases/download/v3.11.2/json.hpp

    cat << 'EOF' > /home/user/dictionary.txt
admin
password123
qwerty
letmein
supersecret
welcome
123456
EOF

    cat << 'EOF' > /home/user/deployments.json
[
  {
    "app_name": "FrontendApp",
    "admin_hash": "5f4dcc3b5aa765d61d8327deb882cf99",
    "csp_header": "default-src 'self'; script-src 'self' 'unsafe-inline'"
  },
  {
    "app_name": "BackendAPI",
    "admin_hash": "8843d7f92416211de9ebb963ff4ce281",
    "csp_header": "default-src 'self'; frame-ancestors 'none'"
  },
  {
    "app_name": "AdminPanel",
    "admin_hash": "d8578edf8458ce06fbc5bb76a58c5ca4",
    "csp_header": "default-src 'none'; script-src https://trusted.cdn.com"
  },
  {
    "app_name": "DataProcessor",
    "admin_hash": "e2fc714c4727ee9395f324cd2e7f331f",
    "csp_header": "script-src 'self' 'unsafe-eval'; style-src 'self'"
  }
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
