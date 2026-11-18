#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs

    cat << 'EOF' > /home/user/configs/system.cfg
log_level=INFO
max_connections=100
EOF

    cat << 'EOF' > /home/user/configs/web.json
{
  "port": 8080,
  "host": "0.0.0.0"
}
EOF

    dd if=/dev/zero of=/home/user/configs/large_data.bin bs=1M count=2
    echo "patch" >> /home/user/configs/large_data.bin

    cat << 'EOF' > /home/user/configs/new_module.conf
enabled=true
EOF

    cat << 'EOF' > /home/user/base_manifest.txt
b6d81b360a5672d80c27430f39153e2c140a6e47388170c8a6f6984d72023dcb large_data.bin
3e2260eb7f9fcff8a9391ab63897b7642ce74f009d1366914620023a10be28ed system.cfg
fa232b7bb115ab323d8c2ea710b7762d001944da2b7bceefb0e77d710dbdf1aa web.json
EOF

    chmod -R 777 /home/user
