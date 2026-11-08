#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backend

    cat << 'EOF' > /home/user/blocked.txt
/admin
/private/
/api/v1/secret
EOF

    echo "OK" > /home/user/backend/index.html
    echo "ADMIN" > /home/user/backend/admin.html
    echo "PUBLIC" > /home/user/backend/public.txt

    chmod -R 777 /home/user
