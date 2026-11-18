#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/manifests
    cat << 'EOF' > /home/user/manifests/vms.json
{
  "vms": [
    {
      "name": "web-server",
      "memory": "2G",
      "vnc_port": 5901,
      "image": "/home/user/images/web.img"
    },
    {
      "name": "db-server",
      "memory": "4G",
      "image": "/home/user/images/db.img"
    },
    {
      "name": "cache-server",
      "memory": "1G",
      "vnc_port": 5903
    }
  ]
}
EOF

    chmod -R 777 /home/user
