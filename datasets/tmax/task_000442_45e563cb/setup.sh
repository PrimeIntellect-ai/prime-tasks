#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip iproute2 iputils-ping
    pip3 install pytest

    mkdir -p /home/user/storage_dir
    dd if=/dev/urandom of=/home/user/storage_dir/data.bin bs=1024 count=500
    cat << 'EOF' > /home/user/manifest.json
{
  "max_storage_kb": 10240
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
