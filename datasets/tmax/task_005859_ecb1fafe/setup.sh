#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_config
    cat << 'EOF' > /home/user/app_config/creds.json
{
  "api_key_b64": "b2xkX3NlY3JldF90b2tlbl8xMjM="
}
EOF

    chmod -R 777 /home/user
    chmod 644 /home/user/app_config/creds.json
