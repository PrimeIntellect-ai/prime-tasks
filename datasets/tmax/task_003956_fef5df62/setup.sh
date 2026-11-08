#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang systemd
    pip3 install pytest

    mkdir -p /home/user/data /home/user/src

    cat << 'EOF' > /home/user/data/requests.log
1690000000 200 /api/v1/data
1690000001 200 /api/v1/data
1690000002 404 /api/v1/missing
1690000003 500 /api/v1/error
1690000004 200 /api/v1/data
1690000005 401 /api/v1/secret
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
