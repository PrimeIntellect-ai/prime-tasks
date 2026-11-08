#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest packaging

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/manifests

    cat << 'EOF' > /home/user/system_state.txt
Module: auth-service Version: 2.1.0
Module: db-driver Version: 1.5.4
Module: ui-components Version: 3.0.0
Module: payment-gateway Version: 1.0.2
EOF

    cat << 'EOF' > /home/user/manifests/manifest_1.json
{
  "manifest_id": "core-update-v2",
  "constraint": "(auth-service >= 2.0.0 & db-driver < 2.0.0)"
}
EOF

    cat << 'EOF' > /home/user/manifests/manifest_2.json
{
  "manifest_id": "ui-hotfix",
  "constraint": "(ui-components > 3.0.0 | auth-service == 2.1.0) & !(payment-gateway < 1.0.0)"
}
EOF

    cat << 'EOF' > /home/user/manifests/manifest_3.json
{
  "manifest_id": "legacy-db-rollback",
  "constraint": "(db-driver <= 1.5.0) | (non-existent-module == 1.0.0)"
}
EOF

    cat << 'EOF' > /home/user/manifests/manifest_4.json
{
  "manifest_id": "complex-gateway",
  "constraint": "!(payment-gateway >= 1.1.0) & (ui-components == 3.0.0 & db-driver >= 1.5.0)"
}
EOF

    chmod -R 777 /home/user
