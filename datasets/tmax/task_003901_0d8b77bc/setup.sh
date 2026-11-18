#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user/project
    cat << 'EOF' > /home/user/project/routes.txt
/api/v1/users/{id} -> GetUser
/api/v1/products/{id} -> GetProduct
/api/v1/orders/{category}/{id}/status -> CheckOrderStatus
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
