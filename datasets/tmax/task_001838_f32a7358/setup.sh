#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/bin
    cp /bin/ls /home/user/bin/app_ls
    cp /bin/cat /home/user/bin/app_cat
    echo "config=true" > /home/user/bin/config.txt
    echo "data" > /home/user/bin/data.dat

    cat << 'EOF' > /home/user/deploy.json
{
  "deployments": [
    {"id": "job-101", "path": "/home/user/bin/app_ls"},
    {"id": "job-102", "path": "/home/user/bin/config.txt"},
    {"id": "job-103", "path": "/home/user/bin/app_cat"},
    {"id": "job-104", "path": "/home/user/bin/data.dat"}
  ]
}
EOF

    chmod -R 777 /home/user
