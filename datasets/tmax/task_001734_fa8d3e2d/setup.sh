#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq tar
    pip3 install pytest

    mkdir -p /home/user/vm_data/disks
    mkdir -p /home/user/cold_storage

    touch /home/user/vm_data/disks/ubuntu_web_01.qcow2
    touch /home/user/vm_data/disks/db_backend_02.qcow2
    touch /home/user/vm_data/disks/legacy_app_99.qcow2
    touch /home/user/vm_data/disks/test_env_alpha.qcow2
    touch /home/user/vm_data/disks/cache_node_05.qcow2

    cat << 'EOF' > /home/user/vm_data/manifest.json
[
  {
    "vm_id": "web-server-01",
    "disk_image": "ubuntu_web_01.qcow2",
    "connections": ["10.0.0.5:80", "10.0.0.6:443"]
  },
  {
    "vm_id": "database-main",
    "disk_image": "db_backend_02.qcow2",
    "connections": ["10.0.0.10:5432"]
  },
  {
    "vm_id": "legacy-app-old",
    "disk_image": "legacy_app_99.qcow2",
    "connections": []
  },
  {
    "vm_id": "alpha-testing",
    "disk_image": "test_env_alpha.qcow2",
    "connections": []
  },
  {
    "vm_id": "redis-cache",
    "disk_image": "cache_node_05.qcow2",
    "connections": ["10.0.1.55:6379"]
  }
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
