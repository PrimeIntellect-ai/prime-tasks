#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_topology.csv
ServiceName,LegacyIP,LegacyPort,CloudDBHost,NewPort,TargetGroup
AuthService,192.168.1.10,8080,db-auth.cloud.internal,9000,auth_admins
PaymentGateway,192.168.1.12,443,db-pay.cloud.internal,8443,fin_ops
InventoryWorker,10.0.0.5,5050,db-inv.cloud.internal,8050,warehouse_sys
EOF

    chmod -R 777 /home/user
