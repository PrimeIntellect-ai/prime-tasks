#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx jq
    pip3 install pytest pyyaml

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/routes.yaml
services:
  - name: auth-service
    path: /api/v1/auth
    target: http://127.0.0.1:5001
  - name: billing-service
    path: /api/v1/billing
    target: http://127.0.0.1:5002
  - name: catalog-service
    path: /api/v2/catalog
    target: http://127.0.0.1:5003
EOF

    chmod -R 777 /home/user
