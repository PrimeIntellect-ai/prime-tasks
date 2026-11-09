#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/manifests

    cat << 'EOF' > /home/user/manifests/web.json
{
  "metadata": {"name": "web-server"},
  "spec": {
    "qemu_image": "/var/lib/images/web.qcow2",
    "vnc_port": 5901,
    "memory": "1024M"
  }
}
EOF

    cat << 'EOF' > /home/user/manifests/db.json
{
  "metadata": {"name": "db-server"},
  "spec": {
    "qemu_image": "/var/lib/images/db.qcow2",
    "vnc_port": 5902,
    "memory": "4096M"
  }
}
EOF

    chmod -R 777 /home/user
