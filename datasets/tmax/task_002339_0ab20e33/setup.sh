#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl jq
    pip3 install pytest

    mkdir -p /home/user/workspace/artifacts
    cd /home/user/workspace/artifacts

    dd if=/dev/zero of=build_alpha.tar bs=1 count=10240 2>/dev/null
    dd if=/dev/zero of=build_beta.tar bs=1 count=15000 2>/dev/null
    dd if=/dev/zero of=build_gamma.tar bs=1 count=20480 2>/dev/null
    dd if=/dev/zero of=build_delta.tar bs=1 count=5000 2>/dev/null

    cat << 'EOF' > manifest.json
{
  "artifacts": [
    {"filename": "build_alpha.tar", "expected_parity": 20},
    {"filename": "build_beta.tar", "expected_parity": 100},
    {"filename": "build_gamma.tar", "expected_parity": 137},
    {"filename": "build_delta.tar", "expected_parity": 50}
  ]
}
EOF

    mkdir -p /tmp/client_body /tmp/proxy_temp /tmp/fastcgi_temp /tmp/uwsgi_temp /tmp/scgi_temp
    chmod 777 /tmp/client_body /tmp/proxy_temp /tmp/fastcgi_temp /tmp/uwsgi_temp /tmp/scgi_temp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
